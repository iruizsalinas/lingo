defmodule Lingo.Voice.Connection.Signal do
  @moduledoc false

  # The voice gateway side of a voice connection: identify and resume,
  # opcodes, DAVE messages, closes and reconnects. Functions take the
  # connection's state and return GenServer results.

  require Logger

  alias Lingo.Gateway.WebSocket
  alias Lingo.Voice.Connection
  alias Lingo.Voice.Connection.{Opcodes, Playback}
  alias Lingo.Voice.Dave.Session, as: Dave

  # closes after which resuming can't work
  @fatal_codes [4004, 4006, 4011, 4012, 4014, 4016, 4017, 4020, 4021, 4022]
  @max_attempts 5

  # connecting blocks through the TLS and HTTP handshakes, so a task does it
  def connect(state) do
    owner = self()
    url = "wss://#{state.endpoint}/?v=8"

    task =
      Task.async(fn ->
        with {:ok, ws} <- WebSocket.connect(url),
             :ok <- WebSocket.controlling_process(ws, owner) do
          {:ok, ws}
        end
      end)

    %{state | connect_task: task}
  end

  def heartbeat(%{awaiting_ack?: true} = state) do
    Logger.warning("Lingo voice #{state.guild_id}: heartbeat not acknowledged, resuming")
    reconnect(state)
  end

  def heartbeat(state) do
    send_json(state, 3, %{t: System.system_time(:millisecond), seq_ack: state.seq})
    timer = Process.send_after(self(), :heartbeat, state.heartbeat_interval)
    {:noreply, %{state | heartbeat_timer: timer, awaiting_ack?: true}}
  end

  # resume on a fresh socket, or identify the first time
  def hello(%{resuming?: true} = state) do
    send_json(state, 7, %{
      server_id: to_string(state.guild_id),
      session_id: state.session_id,
      token: state.token,
      seq_ack: state.seq
    })

    state
  end

  def hello(state) do
    send_json(state, 0, %{
      server_id: to_string(state.guild_id),
      user_id: to_string(state.user_id),
      session_id: state.session_id,
      token: state.token,
      max_dave_protocol_version: Dave.max_protocol_version()
    })

    %{state | status: :identifying}
  end

  def handle_frames([], state), do: {:noreply, state}

  def handle_frames([frame | rest], state) do
    ws = state.ws

    case handle_frame(frame, state) do
      # Frames already decoded from a socket that just closed are stale.
      {:noreply, %{ws: ^ws} = state} -> handle_frames(rest, state)
      result -> result
    end
  end

  def close(code, state) when code in @fatal_codes do
    Logger.warning("Lingo voice #{state.guild_id}: closed with #{code}, not reconnecting")
    Connection.notify(state, {:disconnected, code})
    {:stop, {:shutdown, {:closed, code}}, state}
  end

  def close(reason, state) do
    Logger.info("Lingo voice #{state.guild_id}: connection lost (#{inspect(reason)}), resuming")
    reconnect(state)
  end

  # resumes on a fresh socket; the server replays what we missed
  def reconnect(state) do
    if state.ws, do: WebSocket.close(state.ws)
    if state.heartbeat_timer, do: Process.cancel_timer(state.heartbeat_timer)

    # resuming needs an established session, otherwise identify again
    resuming? = state.status == :connected or state.resuming?

    retry(
      %{state | ws: nil, heartbeat_timer: nil, awaiting_ack?: false, resuming?: resuming?},
      :reconnect
    )
  end

  def retry(%{attempts: attempts} = state, reason) when attempts >= @max_attempts do
    Connection.notify(state, {:disconnected, reason})
    {:stop, {:shutdown, {:connection_failed, reason}}, state}
  end

  def retry(state, _reason) do
    Process.send_after(self(), :connect, 1_000 * (state.attempts + 1))
    {:noreply, %{state | attempts: state.attempts + 1}}
  end

  def send_dave(state, messages) do
    Enum.each(messages, fn
      {:json, op, data} -> send_json(state, op, data)
      {:binary, op, payload} -> send_binary(state, op, payload)
    end)

    state
  end

  def send_json(%{ws: nil}, _op, _data), do: :ok

  def send_json(%{ws: ws}, op, data),
    do: WebSocket.send_frame(ws, {:text, JSON.encode!(%{op: op, d: data})})

  defp send_binary(%{ws: nil}, _op, _payload), do: :ok

  defp send_binary(%{ws: ws}, op, payload),
    do: WebSocket.send_frame(ws, {:binary, <<op>> <> payload})

  defp handle_frame({:text, json}, state) do
    case JSON.decode(json) do
      {:ok, %{"op" => op} = message} ->
        # payloads carry secrets (the transport key), so only the opcode is logged
        Logger.debug("Lingo voice #{state.guild_id}: op #{op}")
        state = if is_integer(message["seq"]), do: %{state | seq: message["seq"]}, else: state
        Opcodes.handle(op, message["d"], state)

      _invalid ->
        {:noreply, state}
    end
  end

  defp handle_frame({:binary, <<seq::16, op, payload::binary>>}, state) do
    Logger.debug("Lingo voice #{state.guild_id}: binary op #{op} (#{byte_size(payload)} bytes)")
    {dave, messages} = Dave.handle_binary(state.dave, op, payload, Connection.now())
    {:noreply, %{state | seq: seq, dave: dave} |> send_dave(messages) |> Playback.check_ready()}
  end

  defp handle_frame({:binary, _short}, state), do: {:noreply, state}
  defp handle_frame({:close, code, _reason}, state), do: close(code, state)
end
