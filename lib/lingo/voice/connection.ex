defmodule Lingo.Voice.Connection do
  @moduledoc """
  A connection to a Discord voice server (voice gateway v8): one per guild.

  It takes the session details the main gateway hands out (`session_id` from
  VOICE_STATE_UPDATE, `token` and `endpoint` from VOICE_SERVER_UPDATE), so it
  depends on nothing global and several bots can run side by side.

  Media is end-to-end encrypted with DAVE whenever the call uses it, then
  transport encrypted over UDP. Subscribers receive:

    * `{:lingo_voice, guild_id, :ready}` once connected; with DAVE on, audio
      is only sent once the group keys are in place (see `info/1`)
    * `{:lingo_voice, guild_id, {:audio, user_id, packet}}` for each Opus packet
      received, where `packet` has `:opus`, `:sequence` and `:timestamp`
    * `{:lingo_voice, guild_id, {:speaking, user_id, flags}}`
    * `{:lingo_voice, guild_id, :playback_finished}`
    * `{:lingo_voice, guild_id, {:playback_failed, reason}}` when the audio
      source fails, for example ffmpeg can't read the input
    * `{:lingo_voice, guild_id, {:disconnected, reason}}`
  """

  use GenServer, restart: :temporary

  import Bitwise

  alias Lingo.Gateway.WebSocket
  alias Lingo.Voice.Dave.Session, as: Dave
  alias Lingo.Voice.{Opus, Player, RTP}

  require Logger

  # closes after which resuming can't work
  @fatal_codes [4004, 4006, 4011, 4012, 4014, 4016, 4017, 4020, 4021, 4022]
  @max_attempts 5
  @discovery_attempts 5
  @keepalive_interval 5_000
  @max_unmapped_ssrcs 8
  @max_unmapped_packets 50

  @enforce_keys [:guild_id, :channel_id, :user_id, :session_id, :token, :endpoint]
  defstruct [
    :guild_id,
    :channel_id,
    :user_id,
    :session_id,
    :token,
    :endpoint,
    :ws,
    :connect_task,
    :heartbeat_timer,
    :heartbeat_interval,
    :udp,
    :remote,
    :ssrc,
    :mode,
    :secret_key,
    :dave,
    :player,
    # packets to play once audio can be sent
    :pending,
    status: :connecting,
    seq: -1,
    ready?: false,
    resuming?: false,
    attempts: 0,
    discovery_attempts: 0,
    awaiting_ack?: false,
    speaking?: false,
    nonce: 0,
    sequence: 0,
    timestamp: 0,
    keepalive: 0,
    ssrc_users: %{},
    # packets from SSRCs not yet tied to a user, newest first
    unmapped: %{},
    subscribers: %{}
  ]

  ## API

  @doc """
  Starts a connection.

  Required options: `:guild_id`, `:channel_id`, `:user_id`, `:session_id`,
  `:token` and `:endpoint`. Optional: `:subscriber` (a pid notified of
  events) and `:name`.
  """
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))

  @doc "Plays a stream of Opus packets, replacing whatever is playing."
  @spec play(GenServer.server(), Enumerable.t()) :: :ok
  def play(connection, packets), do: GenServer.call(connection, {:play, packets})

  @spec stop_playback(GenServer.server()) :: :ok
  def stop_playback(connection), do: GenServer.call(connection, :stop_playback)

  @spec subscribe(GenServer.server(), pid()) :: :ok
  def subscribe(connection, pid \\ self()), do: GenServer.call(connection, {:subscribe, pid})

  @doc "The connection's state: status, readiness, SSRC, encryption details."
  @spec info(GenServer.server()) :: map()
  def info(connection), do: GenServer.call(connection, :info)

  @spec disconnect(GenServer.server()) :: :ok
  def disconnect(connection), do: GenServer.stop(connection, :normal)

  ## Lifecycle

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    state = %__MODULE__{
      guild_id: to_integer(Keyword.fetch!(opts, :guild_id)),
      channel_id: to_integer(Keyword.fetch!(opts, :channel_id)),
      user_id: to_integer(Keyword.fetch!(opts, :user_id)),
      session_id: Keyword.fetch!(opts, :session_id),
      token: Keyword.fetch!(opts, :token),
      endpoint: Keyword.fetch!(opts, :endpoint),
      sequence: :rand.uniform(0xFFFF),
      timestamp: :rand.uniform(0xFFFFFFFF)
    }

    state = %{state | dave: Dave.new(state.user_id, state.channel_id)}
    state = if pid = opts[:subscriber], do: add_subscriber(state, pid), else: state

    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.ws, do: WebSocket.close(state.ws)
    if state.udp, do: :gen_udp.close(state.udp)
    :ok
  end

  @impl true
  def handle_call({:play, packets}, _from, state),
    do: {:reply, :ok, %{stop_player(state) | pending: packets} |> start_pending()}

  def handle_call(:stop_playback, _from, state),
    do: {:reply, :ok, %{stop_player(state) | pending: nil} |> set_speaking(false)}

  def handle_call({:subscribe, pid}, _from, state) do
    state = add_subscriber(state, pid)
    if state.ready?, do: send(pid, {:lingo_voice, state.guild_id, :ready})
    {:reply, :ok, state}
  end

  def handle_call(:info, _from, state) do
    info = %{
      status: state.status,
      ready?: state.ready?,
      playback: playback(state),
      ssrc: state.ssrc,
      mode: state.mode,
      dave_protocol_version: state.dave.protocol_version,
      dave_active?: Dave.active?(state.dave),
      epoch_authenticator: Dave.epoch_authenticator(state.dave)
    }

    {:reply, info, state}
  end

  ## Voice gateway connection

  @impl true
  def handle_info(:connect, state) do
    owner = self()
    url = "wss://#{state.endpoint}/?v=8"

    task =
      Task.async(fn ->
        with {:ok, ws} <- WebSocket.connect(url),
             :ok <- WebSocket.controlling_process(ws, owner) do
          {:ok, ws}
        end
      end)

    {:noreply, %{state | connect_task: task}}
  end

  def handle_info({ref, result}, %{connect_task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    state = %{state | connect_task: nil}

    with {:ok, ws} <- result, :ok <- WebSocket.activate(ws) do
      {:noreply, %{state | ws: ws} |> send_hello_response()}
    else
      {:error, reason} -> retry(state, reason)
    end
  end

  def handle_info(:heartbeat, %{awaiting_ack?: true} = state) do
    Logger.warning("Lingo voice #{state.guild_id}: heartbeat not acknowledged, resuming")
    reconnect(state)
  end

  def handle_info(:heartbeat, state) do
    send_json(state, 3, %{t: System.system_time(:millisecond), seq_ack: state.seq})
    timer = Process.send_after(self(), :heartbeat, state.heartbeat_interval)
    {:noreply, %{state | heartbeat_timer: timer, awaiting_ack?: true}}
  end

  def handle_info(:discover, %{status: :discovering} = state) do
    if state.discovery_attempts < @discovery_attempts do
      :gen_udp.send(
        state.udp,
        elem(state.remote, 0),
        elem(state.remote, 1),
        RTP.discovery_request(state.ssrc)
      )

      Process.send_after(self(), :discover, 1_000)
      {:noreply, %{state | discovery_attempts: state.discovery_attempts + 1}}
    else
      {:stop, {:shutdown, :ip_discovery_failed}, state}
    end
  end

  def handle_info(:discover, state), do: {:noreply, state}

  # keeps the NAT mapping open while we only listen
  def handle_info(:keepalive, %{udp: udp, remote: {ip, port}} = state) when udp != nil do
    :gen_udp.send(udp, ip, port, <<state.keepalive::32-little, 0::32>>)
    Process.send_after(self(), :keepalive, @keepalive_interval)
    {:noreply, %{state | keepalive: state.keepalive + 1 &&& 0xFFFFFFFF}}
  end

  def handle_info({:udp, udp, _ip, _port, packet}, %{udp: udp} = state),
    do: handle_udp(packet, state)

  def handle_info({:player_frame, player, opus}, %{player: player} = state),
    do: {:noreply, send_audio(state, opus)}

  def handle_info({:player_done, player}, %{player: player} = state) do
    notify(state, :playback_finished)
    {:noreply, %{state | player: nil} |> set_speaking(false)}
  end

  def handle_info({:EXIT, player, reason}, %{player: player} = state) when reason != :normal do
    reason =
      case reason do
        {exception, _stacktrace} when is_exception(exception) -> exception
        reason -> reason
      end

    Logger.error("Lingo voice #{state.guild_id}: playback failed: #{inspect(reason)}")
    notify(state, {:playback_failed, reason})
    {:noreply, %{state | player: nil} |> set_speaking(false)}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state),
    do: {:noreply, %{state | subscribers: Map.delete(state.subscribers, pid)}}

  def handle_info(message, %{ws: %WebSocket{} = ws} = state) do
    case WebSocket.stream(ws, message) do
      {:ok, ws, frames} -> handle_frames(frames, %{state | ws: ws})
      {:error, _ws, reason} -> handle_close(reason, state)
      :unknown -> {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp send_hello_response(%{resuming?: true} = state) do
    send_json(state, 7, %{
      server_id: to_string(state.guild_id),
      session_id: state.session_id,
      token: state.token,
      seq_ack: state.seq
    })

    state
  end

  defp send_hello_response(state) do
    send_json(state, 0, %{
      server_id: to_string(state.guild_id),
      user_id: to_string(state.user_id),
      session_id: state.session_id,
      token: state.token,
      max_dave_protocol_version: Dave.max_protocol_version()
    })

    %{state | status: :identifying}
  end

  defp handle_frames([], state), do: {:noreply, state}

  defp handle_frames([frame | rest], state) do
    case handle_frame(frame, state) do
      {:noreply, state} -> handle_frames(rest, state)
      stop -> stop
    end
  end

  defp handle_frame({:text, json}, state) do
    case JSON.decode(json) do
      {:ok, %{"op" => op} = message} ->
        # payloads carry secrets (the transport key), so only the opcode is logged
        Logger.debug("Lingo voice #{state.guild_id}: op #{op}")
        state = if is_integer(message["seq"]), do: %{state | seq: message["seq"]}, else: state
        handle_op(op, message["d"], state)

      _invalid ->
        {:noreply, state}
    end
  end

  defp handle_frame({:binary, <<seq::16, op, payload::binary>>}, state) do
    Logger.debug("Lingo voice #{state.guild_id}: binary op #{op} (#{byte_size(payload)} bytes)")
    {dave, messages} = Dave.handle_binary(state.dave, op, payload, now())
    {:noreply, %{state | seq: seq, dave: dave} |> send_dave(messages) |> check_ready()}
  end

  defp handle_frame({:binary, _short}, state), do: {:noreply, state}
  defp handle_frame({:close, code, _reason}, state), do: handle_close(code, state)

  ## Voice gateway opcodes

  # Hello
  defp handle_op(8, %{"heartbeat_interval" => interval}, state) do
    if state.heartbeat_timer, do: Process.cancel_timer(state.heartbeat_timer)
    send(self(), :heartbeat)
    {:noreply, %{state | heartbeat_interval: trunc(interval), awaiting_ack?: false}}
  end

  # Ready: open the UDP socket and find our public address
  defp handle_op(2, %{"ssrc" => ssrc, "ip" => ip, "port" => port, "modes" => modes}, state) do
    with mode when mode != nil <- RTP.choose_mode(modes),
         {:ok, address} <- :inet.parse_address(String.to_charlist(ip)),
         {:ok, udp} <- :gen_udp.open(0, [:binary, active: true]) do
      if state.udp, do: :gen_udp.close(state.udp)
      send(self(), :discover)

      {:noreply,
       %{
         state
         | ssrc: ssrc,
           mode: mode,
           udp: udp,
           remote: {address, port},
           status: :discovering,
           discovery_attempts: 0
       }}
    else
      error -> {:stop, {:shutdown, {:udp_setup_failed, error}}, state}
    end
  end

  # Session Description: transport key and DAVE version
  defp handle_op(4, %{"secret_key" => key, "mode" => mode} = data, state) do
    version = data["dave_protocol_version"] || 0
    {dave, messages} = Dave.set_protocol_version(state.dave, version, now())
    Process.send_after(self(), :keepalive, @keepalive_interval)

    state = %{
      state
      | secret_key: :binary.list_to_bin(key),
        mode: mode,
        dave: dave,
        status: :connected,
        attempts: 0
    }

    {:noreply, state |> send_dave(messages) |> check_ready()}
  end

  # Speaking: also how we learn which user an SSRC belongs to
  defp handle_op(5, %{"user_id" => user_id, "ssrc" => ssrc} = data, state) do
    user_id = to_integer(user_id)
    notify(state, {:speaking, user_id, data["speaking"]})

    # a speaker's first packets often beat this message here; hear them now
    {early, unmapped} = Map.pop(state.unmapped, ssrc, [])
    state = %{state | ssrc_users: Map.put(state.ssrc_users, ssrc, user_id), unmapped: unmapped}

    {:noreply,
     early
     |> Enum.reverse()
     |> Enum.reduce(state, fn {header, opus}, state -> deliver(state, user_id, header, opus) end)}
  end

  # Heartbeat ACK
  defp handle_op(6, _data, state), do: {:noreply, %{state | awaiting_ack?: false}}

  # Resumed
  defp handle_op(9, _data, state) do
    {:noreply, %{state | resuming?: false, status: :connected, attempts: 0} |> check_ready()}
  end

  # Clients Connect
  defp handle_op(11, %{"user_ids" => user_ids}, state) do
    {:noreply,
     %{state | dave: Dave.clients_connect(state.dave, Enum.map(user_ids, &to_integer/1))}}
  end

  # Client Disconnect
  defp handle_op(13, %{"user_id" => user_id}, state) do
    user_id = to_integer(user_id)
    ssrc_users = Map.reject(state.ssrc_users, fn {_ssrc, id} -> id == user_id end)

    {:noreply,
     %{state | dave: Dave.client_disconnect(state.dave, user_id), ssrc_users: ssrc_users}}
  end

  # DAVE transitions and epochs
  defp handle_op(op, data, state) when op in [21, 22, 24] and is_map(data) do
    {dave, messages} = Dave.handle_json(state.dave, op, data, now())
    {:noreply, %{state | dave: dave} |> send_dave(messages) |> check_ready()}
  end

  defp handle_op(_op, _data, state), do: {:noreply, state}

  defp handle_close(code, state) when code in @fatal_codes do
    Logger.warning("Lingo voice #{state.guild_id}: closed with #{code}, not reconnecting")
    notify(state, {:disconnected, code})
    {:stop, {:shutdown, {:closed, code}}, state}
  end

  defp handle_close(reason, state) do
    Logger.info("Lingo voice #{state.guild_id}: connection lost (#{inspect(reason)}), resuming")
    reconnect(state)
  end

  # resumes on a fresh socket; the server replays what we missed
  defp reconnect(state) do
    if state.ws, do: WebSocket.close(state.ws)
    if state.heartbeat_timer, do: Process.cancel_timer(state.heartbeat_timer)

    state = %{state | ws: nil, heartbeat_timer: nil, awaiting_ack?: false}
    # resuming needs an established session, otherwise identify again
    state = %{state | resuming?: state.status == :connected or state.resuming?}
    retry(state, :reconnect)
  end

  defp retry(%{attempts: attempts} = state, reason) when attempts >= @max_attempts do
    notify(state, {:disconnected, reason})
    {:stop, {:shutdown, {:connection_failed, reason}}, state}
  end

  defp retry(state, _reason) do
    Process.send_after(self(), :connect, 1_000 * (state.attempts + 1))
    {:noreply, %{state | attempts: state.attempts + 1}}
  end

  ## UDP

  defp handle_udp(packet, %{status: :discovering} = state) do
    case RTP.parse_discovery(packet) do
      {:ok, ip, port} ->
        send_json(state, 1, %{protocol: "udp", data: %{address: ip, port: port, mode: state.mode}})

        {:noreply, %{state | status: :selecting}}

      :error ->
        {:noreply, state}
    end
  end

  defp handle_udp(packet, %{secret_key: key} = state) when key != nil do
    with true <- RTP.voice_packet?(packet),
         {:ok, header, opus} <- RTP.decrypt(state.mode, key, packet) do
      case Map.fetch(state.ssrc_users, header.ssrc) do
        {:ok, user_id} -> {:noreply, deliver(state, user_id, header, opus)}
        :error -> {:noreply, hold_unmapped(state, header, opus)}
      end
    else
      _not_audio -> {:noreply, state}
    end
  end

  defp handle_udp(_packet, state), do: {:noreply, state}

  defp deliver(state, user_id, header, opus) do
    case Dave.decrypt(state.dave, user_id, opus, now()) do
      {:ok, opus, dave} ->
        packet = %{opus: opus, sequence: header.sequence, timestamp: header.timestamp}
        notify(state, {:audio, user_id, packet})
        %{state | dave: dave}

      {:error, _reason, dave} ->
        %{state | dave: dave}
    end
  end

  # kept until a Speaking message says whose they are; a second's worth per
  # SSRC, for a handful of SSRCs, so stray traffic can't pile up
  defp hold_unmapped(%{unmapped: unmapped} = state, header, opus) do
    if Map.has_key?(unmapped, header.ssrc) or map_size(unmapped) < @max_unmapped_ssrcs do
      held =
        [{header, opus} | Map.get(unmapped, header.ssrc, [])] |> Enum.take(@max_unmapped_packets)

      %{state | unmapped: Map.put(unmapped, header.ssrc, held)}
    else
      state
    end
  end

  ## Sending audio

  defp send_audio(%{secret_key: nil} = state, _opus), do: state

  defp send_audio(state, opus) do
    case Dave.encrypt(state.dave, opus) do
      {:ok, frame, dave} ->
        state = set_speaking(%{state | dave: dave}, true)
        header = %{sequence: state.sequence, timestamp: state.timestamp, ssrc: state.ssrc}
        packet = RTP.encrypt(state.mode, state.secret_key, header, state.nonce, frame)
        {ip, port} = state.remote
        :gen_udp.send(state.udp, ip, port, packet)

        %{
          state
          | sequence: state.sequence + 1 &&& 0xFFFF,
            timestamp: state.timestamp + Opus.samples(opus) &&& 0xFFFFFFFF,
            nonce: state.nonce + 1 &&& 0xFFFFFFFF
        }

      # E2EE is on but our keys aren't ready yet: never send media unencrypted
      {:error, :not_ready} ->
        state
    end
  end

  defp set_speaking(%{speaking?: speaking?} = state, speaking?), do: state
  defp set_speaking(%{ssrc: nil} = state, _speaking?), do: state

  defp set_speaking(state, speaking?) do
    send_json(state, 5, %{speaking: if(speaking?, do: 1, else: 0), delay: 0, ssrc: state.ssrc})
    %{state | speaking?: speaking?}
  end

  defp stop_player(%{player: nil} = state), do: state

  defp stop_player(state) do
    Process.unlink(state.player)
    Process.exit(state.player, :kill)
    %{state | player: nil}
  end

  ## Helpers

  # ready once the transport is up; with DAVE on, media still waits for the
  # group keys, which a lone member never gets until someone else joins
  defp check_ready(%{ready?: false, status: :connected} = state) do
    notify(state, :ready)
    start_pending(%{state | ready?: true})
  end

  defp check_ready(state), do: start_pending(state)

  # Playback starts once audio can actually go out, from its first packet:
  # nothing is lost to a connection still coming up, and a bot alone in an
  # end-to-end encrypted call starts playing when someone joins.
  defp start_pending(%{pending: packets} = state) when packets != nil do
    if can_send?(state) do
      {:ok, player} = Player.start_link(self(), packets)
      %{state | player: player, pending: nil}
    else
      state
    end
  end

  defp start_pending(state), do: state

  defp can_send?(state),
    do: state.status == :connected and state.secret_key != nil and Dave.ready?(state.dave)

  defp playback(%{player: player}) when player != nil, do: :playing
  defp playback(%{pending: pending}) when pending != nil, do: :waiting
  defp playback(_state), do: :idle

  defp send_dave(state, messages) do
    Enum.each(messages, fn
      {:json, op, data} -> send_json(state, op, data)
      {:binary, op, payload} -> send_binary(state, op, payload)
    end)

    state
  end

  defp send_json(%{ws: nil}, _op, _data), do: :ok

  defp send_json(%{ws: ws}, op, data),
    do: WebSocket.send_frame(ws, {:text, JSON.encode!(%{op: op, d: data})})

  defp send_binary(%{ws: nil}, _op, _payload), do: :ok

  defp send_binary(%{ws: ws}, op, payload),
    do: WebSocket.send_frame(ws, {:binary, <<op>> <> payload})

  defp add_subscriber(state, pid) do
    if Map.has_key?(state.subscribers, pid),
      do: state,
      else: %{state | subscribers: Map.put(state.subscribers, pid, Process.monitor(pid))}
  end

  defp notify(state, event),
    do: Enum.each(Map.keys(state.subscribers), &send(&1, {:lingo_voice, state.guild_id, event}))

  defp now, do: System.monotonic_time(:millisecond)

  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_binary(value), do: String.to_integer(value)
end
