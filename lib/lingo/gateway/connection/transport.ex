defmodule Lingo.Gateway.Connection.Transport do
  @moduledoc false

  # The socket side of a gateway connection: connecting, sending, closing and
  # reconnecting. Every function takes and returns the connection's state.

  alias Lingo.Gateway.{Codec, Compression, WebSocket}
  alias Lingo.Gateway.Connection.Outbox

  @hello_timeout 60_000

  # Connecting blocks through the TCP, TLS and HTTP handshakes, so it runs in
  # a task to keep the connection responsive. The task hands the socket over.
  def start_connect(state) do
    url = state.resume_gateway_url || state.gateway_url || "gateway.discord.gg"
    url = gateway_url(url, state.encoding, state.compression)
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
        %{state | state: :awaiting_hello, inflate: inflate(state.compression), hello_timer: timer}

      {:error, _reason} ->
        reconnect(state)
    end
  end

  def reconnect(state, delay \\ nil) do
    state = close(state)
    delay = delay || 1_000 + :rand.uniform(4_000)

    Lingo.Telemetry.execute([:shard, :reconnecting], %{delay: delay}, %{
      shard_id: state.shard_id,
      shard_count: state.shard_count
    })

    if state.connect_timer, do: Process.cancel_timer(state.connect_timer)
    timer = Process.send_after(self(), :connect, delay)
    %{state | state: :disconnected, connect_timer: timer}
  end

  # sends a payload right away, past the queue
  def send_frame(state, payload), do: send_encoded(state, Codec.encode(payload, state.encoding))

  # payloads are queued, and only sent once the session is ready
  def enqueue(state, payload) do
    frame = Codec.encode(payload, state.encoding)
    flush(%{state | outbox: Outbox.push(state.outbox, frame)})
  end

  def flush(%{state: :connected, ws: %WebSocket{}} = state) do
    {frames, outbox, wait} = Outbox.take(state.outbox, System.monotonic_time(:millisecond))
    Enum.each(frames, &send_encoded(state, &1))
    state = %{state | outbox: outbox}

    if wait && state.send_timer == nil,
      do: %{state | send_timer: Process.send_after(self(), :flush_send, wait)},
      else: state
  end

  def flush(state), do: state

  defp send_encoded(%{ws: nil}, _frame), do: :ok
  defp send_encoded(%{ws: ws}, frame), do: WebSocket.send_frame(ws, frame)

  # any code but 1000 and 1001 keeps the session resumable
  def graceful_close(%{ws: nil}), do: :ok
  def graceful_close(%{ws: ws}), do: WebSocket.send_frame(ws, {:close, 4000, ""})

  def close(state) do
    for timer <- [state.hello_timer, state.identify_timer, state.send_timer],
        timer,
        do: Process.cancel_timer(timer)

    if state.inflate, do: Compression.close(state.inflate)
    if state.connect_task, do: cancel_connect(state.connect_task)
    if state.ws, do: WebSocket.close(state.ws)

    %{
      stop_heartbeat(state)
      | ws: nil,
        connect_task: nil,
        inflate: nil,
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

  defp inflate(:none), do: nil
  defp inflate(type), do: Compression.new(type)

  defp gateway_url(url, encoding, compression) do
    uri = URI.parse(if url =~ "://", do: url, else: "wss://" <> url)
    query = [v: 10, encoding: encoding] ++ compress_param(compression)
    URI.to_string(%{uri | path: "/", query: URI.encode_query(query)})
  end

  defp compress_param(:none), do: []
  defp compress_param(type), do: [compress: "#{type}-stream"]
end
