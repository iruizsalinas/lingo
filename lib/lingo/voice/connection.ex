defmodule Lingo.Voice.Connection do
  @moduledoc """
  A connection to a Discord voice server (voice gateway v8): one per guild.

  It takes the session details the main gateway hands out (`session_id` from
  VOICE_STATE_UPDATE, `token` and `endpoint` from VOICE_SERVER_UPDATE), so it
  depends on nothing global and several bots can run side by side.

  Media is end-to-end encrypted with DAVE whenever the call uses it, then
  transport encrypted over UDP. Subscribers receive:

    * `{:lingo_voice, guild_id, :ready}` once connected; with DAVE on, audio
      is only sent once the group keys are in place, so playback asked for
      before then waits and starts from its first packet (see `info/1`)
    * `{:lingo_voice, guild_id, {:audio, user_id, packet}}` for each Opus packet
      received, where `packet` has `:opus`, `:sequence` and `:timestamp`
    * `{:lingo_voice, guild_id, {:speaking, user_id, flags}}`
    * `{:lingo_voice, guild_id, :playback_finished}`
    * `{:lingo_voice, guild_id, {:playback_failed, reason}}` when the audio
      source fails, for example ffmpeg can't read the input
    * `{:lingo_voice, guild_id, {:disconnected, reason}}`
  """

  use GenServer, restart: :temporary

  # This module is the process and routes its messages; Signal speaks the
  # voice gateway and Media the UDP side.

  alias Lingo.Gateway.WebSocket
  alias Lingo.Voice.Connection.{Media, Playback, Signal}
  alias Lingo.Voice.Dave.Session, as: Dave

  @enforce_keys [:guild_id, :channel_id, :user_id, :session_id, :token, :endpoint]
  defstruct [
    :guild_id,
    :channel_id,
    :user_id,
    :session_id,
    :token,
    :endpoint,
    :manager,
    :manager_ref,
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
      manager: opts[:manager],
      sequence: :rand.uniform(0xFFFF),
      timestamp: :rand.uniform(0xFFFFFFFF)
    }

    state = %{state | dave: Dave.new(state.user_id, state.channel_id)}

    state =
      if state.manager, do: %{state | manager_ref: Process.monitor(state.manager)}, else: state

    state = if pid = opts[:subscriber], do: add_subscriber(state, pid), else: state

    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    Playback.stop_player(state)
    if state.connect_task, do: Task.shutdown(state.connect_task, :brutal_kill)
    if state.ws, do: WebSocket.close(state.ws)
    if state.udp, do: :gen_udp.close(state.udp)
    :ok
  end

  @impl true
  def handle_call({:play, packets}, _from, state),
    do:
      {:reply, :ok, %{Playback.stop_player(state) | pending: packets} |> Playback.start_pending()}

  def handle_call(:stop_playback, _from, state),
    do: {:reply, :ok, %{Playback.stop_player(state) | pending: nil} |> Media.set_speaking(false)}

  def handle_call({:subscribe, pid}, _from, state) do
    state = add_subscriber(state, pid)
    if state.ready?, do: send(pid, {:lingo_voice, state.guild_id, :ready})
    {:reply, :ok, state}
  end

  def handle_call(:info, _from, state) do
    info = %{
      status: state.status,
      ready?: state.ready?,
      playback: Playback.playback(state),
      ssrc: state.ssrc,
      mode: state.mode,
      dave_protocol_version: state.dave.protocol_version,
      dave_active?: Dave.active?(state.dave),
      epoch_authenticator: Dave.epoch_authenticator(state.dave)
    }

    {:reply, info, state}
  end

  ## Messages

  @impl true
  def handle_info(:connect, state), do: {:noreply, Signal.connect(state)}

  def handle_info({ref, result}, %{connect_task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    state = %{state | connect_task: nil}

    with {:ok, ws} <- result, :ok <- WebSocket.activate(ws) do
      {:noreply, Signal.hello(%{state | ws: ws})}
    else
      {:error, reason} -> Signal.retry(state, reason)
    end
  end

  def handle_info(:heartbeat, state), do: Signal.heartbeat(state)

  def handle_info(:discover, state), do: Media.discover(state)

  def handle_info(:keepalive, %{udp: udp, remote: {_ip, _port}} = state) when udp != nil,
    do: {:noreply, Media.keepalive(state)}

  def handle_info({:udp, udp, _ip, _port, packet}, %{udp: udp} = state),
    do: {:noreply, Media.receive_packet(packet, state)}

  def handle_info({:player_frame, player, opus}, %{player: player} = state),
    do: {:noreply, Media.send_audio(state, opus)}

  def handle_info({:player_done, player}, %{player: player} = state),
    do: {:noreply, Playback.finished(state, :normal)}

  def handle_info({:EXIT, player, reason}, %{player: player} = state) when reason != :normal,
    do: {:noreply, Playback.finished(state, reason)}

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{manager_ref: ref} = state)
      when is_reference(ref),
      do: {:stop, {:shutdown, :manager_down}, state}

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state),
    do: {:noreply, %{state | subscribers: Map.delete(state.subscribers, pid)}}

  def handle_info(message, %{ws: %WebSocket{} = ws} = state) do
    case WebSocket.stream(ws, message) do
      {:ok, ws, frames} -> Signal.handle_frames(frames, %{state | ws: ws})
      {:error, _ws, reason} -> Signal.close(reason, state)
      :unknown -> {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @doc false
  def notify_ready(state) do
    if state.manager, do: send(state.manager, {:lingo_voice_ready, self(), state.guild_id})
    notify(state, :ready)
  end

  @doc false
  def notify(state, event),
    do: Enum.each(Map.keys(state.subscribers), &send(&1, {:lingo_voice, state.guild_id, event}))

  @doc false
  def now, do: System.monotonic_time(:millisecond)

  @doc false
  def to_integer(value) when is_integer(value), do: value
  def to_integer(value) when is_binary(value), do: String.to_integer(value)

  defp add_subscriber(state, pid) do
    if Map.has_key?(state.subscribers, pid),
      do: state,
      else: %{state | subscribers: Map.put(state.subscribers, pid, Process.monitor(pid))}
  end
end
