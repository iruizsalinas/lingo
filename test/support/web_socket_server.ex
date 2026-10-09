defmodule Lingo.Test.WebSocketServer do
  @moduledoc false

  # The server half of a WebSocket over plain TCP, driven step by step by tests.

  alias Lingo.Gateway.WebSocket
  alias Lingo.Gateway.WebSocket.Frame

  @guid "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

  @doc """
  Connects a client to a fresh server and returns `{ws, server_socket}`,
  both owned by the calling process. The client is not activated yet.
  """
  def connect(opts \\ []) do
    {:ok, ws, server} = try_connect(opts)
    {ws, server}
  end

  @doc """
  Like connect/1, but returns the client's result. `:respond` builds the
  handshake response from the client's key.
  """
  def try_connect(opts \\ []) do
    {listen, url} = listen()
    test_pid = self()

    server =
      Task.async(fn ->
        socket = accept(listen, opts)
        :ok = :gen_tcp.controlling_process(socket, test_pid)
        socket
      end)

    result = WebSocket.connect(url, Keyword.drop(opts, [:respond]))
    socket = Task.await(server)

    case result do
      {:ok, ws} -> {:ok, ws, socket}
      {:error, reason} -> {:error, reason, socket}
    end
  end

  @doc "Opens a listening socket and returns it with the URL to connect to."
  def listen do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    {listen, "ws://127.0.0.1:#{port}/gateway?v=10"}
  end

  @doc "Accepts one client and answers its opening handshake."
  def accept(listen, opts \\ []) do
    respond = Keyword.get(opts, :respond, &accept_response/1)

    {:ok, socket} = :gen_tcp.accept(listen, 5_000)
    :gen_tcp.close(listen)
    key = read_request_key(socket)
    :ok = :gen_tcp.send(socket, respond.(key))
    socket
  end

  def accept_response(key) do
    [
      "HTTP/1.1 101 Switching Protocols\r\n",
      "Upgrade: websocket\r\n",
      "Connection: Upgrade\r\n",
      "Sec-WebSocket-Accept: #{accept_key(key)}\r\n",
      "\r\n"
    ]
  end

  def accept_key(key), do: Base.encode64(:crypto.hash(:sha, key <> @guid))

  @doc "Sends an unmasked frame to the client."
  def send_frame(socket, opcode, payload, opts \\ []),
    do: :gen_tcp.send(socket, Frame.encode(opcode, payload, opts))

  @doc "Receives and decodes `count` masked frames sent by the client."
  def recv_frames(socket, count, timeout \\ 1_000),
    do: recv_frames(socket, count, timeout, <<>>, [])

  defp recv_frames(_socket, 0, _timeout, _buffer, acc), do: Enum.reverse(acc)

  defp recv_frames(socket, count, timeout, buffer, acc) do
    case Frame.decode(buffer, masked: true) do
      {:ok, frame, rest} ->
        recv_frames(socket, count - 1, timeout, rest, [frame | acc])

      :more ->
        case :gen_tcp.recv(socket, 0, timeout) do
          {:ok, data} -> recv_frames(socket, count, timeout, buffer <> data, acc)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc "Receives one frame, or returns `{:error, :timeout}`."
  def recv_frame(socket, timeout \\ 1_000) do
    with [frame] <- recv_frames(socket, 1, timeout), do: frame
  end

  defp read_request_key(socket) do
    :ok = :inet.setopts(socket, packet: :http_bin)
    {:ok, {:http_request, :GET, _target, _version}} = :gen_tcp.recv(socket, 0, 5_000)
    :ok = :inet.setopts(socket, packet: :httph_bin)
    headers = read_headers(socket, %{})
    :ok = :inet.setopts(socket, packet: :raw)
    Map.fetch!(headers, "sec-websocket-key")
  end

  defp read_headers(socket, headers) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, {:http_header, _, name, _, value}} ->
        read_headers(socket, Map.put(headers, String.downcase(to_string(name)), value))

      {:ok, :http_eoh} ->
        headers
    end
  end
end
