defmodule Lingo.Gateway.Connection.Transport do
  @moduledoc false

  # The socket side of a gateway connection: connecting, sending, closing and
  # reconnecting. Every function takes and returns the connection's state.

  alias Lingo.Gateway.{Compression, WebSocket}
  alias Lingo.Gateway.Connection.Outbox

  @hello_timeout 60_000

  # Connecting blocks through the TCP, TLS and HTTP handshakes, so it runs in
  # a task to keep the connection responsive. The task hands the socket over.
  def start_connect(state) do
    url = gateway_url(state.resume_gateway_url || state.gateway_url || "gateway.discord.gg")
    owner = self()

    task =
      Task.async(fn ->
        with {:ok, ws} <- WebSocket.connect(url) do
          case WebSocket.controlling_process(ws, owner) do
            :ok ->
              {:ok, ws}

            {:error, reason} ->
              WebSocket.close(ws)
              {:error, reason}
          end
        end
      end)

    %{state | connect_task: task, state: :connecting}
  end

  def connected(state) do
    case WebSocket.activate(state.ws) do
      :ok ->
        timer = Process.send_after(self(), :hello_timeout, @hello_timeout)
        %{state | state: :awaiting_hello, zlib: Compression.new(), hello_timer: timer}

      {:error, _reason} ->
        reconnect(state)
    end
  end

  def reconnect(state, delay \\ nil) do
    Lingo.Gateway.Dispatcher.dispatch(:shard_reconnecting, %{shard_id: state.shard_id})
    state = close(state)
    delay = delay || 1_000 + :rand.uniform(4_000)

    if state.connect_timer, do: Process.cancel_timer(state.connect_timer)
    timer = Process.send_after(self(), :connect, delay)
    %{state | state: :disconnected, connect_timer: timer}
  end

  def send_frame(%{ws: nil}, _data), do: :ok
  def send_frame(%{ws: ws}, data), do: WebSocket.send_frame(ws, {:text, data})

  # payloads are queued, and only sent once the session is ready
  def enqueue(state, data), do: flush(%{state | outbox: Outbox.push(state.outbox, data)})

  def flush(%{state: :connected, ws: %WebSocket{}} = state) do
    {frames, outbox, wait} = Outbox.take(state.outbox, System.monotonic_time(:millisecond))
    Enum.each(frames, &send_frame(state, &1))
    state = %{state | outbox: outbox}

    if wait && state.send_timer == nil,
      do: %{state | send_timer: Process.send_after(self(), :flush_send, wait)},
      else: state
  end

  def flush(state), do: state

  # any code but 1000 and 1001 keeps the session resumable
  def graceful_close(%{ws: nil}), do: :ok
  def graceful_close(%{ws: ws}), do: WebSocket.send_frame(ws, {:close, 4000, ""})

  def close(state) do
    for timer <- [state.hello_timer, state.identify_timer, state.send_timer],
        timer,
        do: Process.cancel_timer(timer)

    if state.zlib, do: Compression.close(state.zlib)
    if state.connect_task, do: cancel_connect(state.connect_task)
    if state.ws, do: WebSocket.close(state.ws)

    %{
      stop_heartbeat(state)
      | ws: nil,
        connect_task: nil,
        zlib: nil,
        hello_timer: nil,
        identify_timer: nil,
        send_timer: nil
    }
  end

  def stop_heartbeat(state) do
    if state.heartbeat_pid && Process.alive?(state.heartbeat_pid) do
      GenServer.stop(state.heartbeat_pid, :normal, 5_000)
    end

    %{state | heartbeat_pid: nil}
  end

  defp cancel_connect(task) do
    case Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, ws}} -> WebSocket.close(ws)
      _other -> :ok
    end
  end

  defp gateway_url(url) do
    uri = URI.parse(if url =~ "://", do: url, else: "wss://" <> url)
    URI.to_string(%{uri | path: "/", query: "v=10&encoding=json&compress=zlib-stream"})
  end
end
