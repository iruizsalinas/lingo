defmodule Lingo.Gateway.WebSocket do
  @moduledoc false

  # A minimal WebSocket client (RFC 6455) over :ssl, or :gen_tcp for ws:// URLs.
  #
  # It owns no process. connect/2 blocks through the TLS and HTTP handshakes
  # and returns a passive socket; the owner then calls activate/1 and feeds
  # every message it receives to stream/2, which re-arms the socket in
  # `active: :once` mode so a fast peer can't flood the owner's mailbox.
  #
  # Pings are answered automatically. Close frames are handed to the caller,
  # which decides whether to reply before calling close/1.

  alias Lingo.Gateway.WebSocket.Frame

  @guid "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  @timeout 10_000
  @max_frame_size 64 * 1024 * 1024
  @max_headers 100
  @max_line_length 8_192

  @enforce_keys [:transport, :socket]
  defstruct [:transport, :socket, :fragment, buffer: <<>>, max_frame_size: @max_frame_size]

  @type t :: %__MODULE__{
          transport: :ssl | :gen_tcp,
          socket: :ssl.sslsocket() | :gen_tcp.socket(),
          fragment: {:text | :binary, iodata(), non_neg_integer()} | nil,
          buffer: binary(),
          max_frame_size: pos_integer()
        }

  @type frame ::
          {:text, binary()}
          | {:binary, binary()}
          | {:ping, binary()}
          | {:pong, binary()}
          | {:close, close_code :: non_neg_integer(), reason :: binary()}

  @doc """
  Opens a connection and performs the opening handshake.

  Options:

    * `:timeout` - for the TCP, TLS and HTTP handshakes together, in ms
    * `:max_frame_size` - the largest frame or reassembled message accepted
  """
  @spec connect(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def connect(url, opts \\ []) do
    deadline = System.monotonic_time(:millisecond) + Keyword.get(opts, :timeout, @timeout)

    with {:ok, transport, uri} <- parse_url(url),
         {:ok, socket} <- open(transport, uri, remaining(deadline)) do
      ws = %__MODULE__{
        transport: transport,
        socket: socket,
        max_frame_size: Keyword.get(opts, :max_frame_size, @max_frame_size)
      }

      case handshake(ws, uri, deadline) do
        :ok ->
          {:ok, ws}

        {:error, reason} ->
          close(ws)
          {:error, reason}
      end
    end
  end

  @doc "Starts delivering socket messages to the owning process."
  @spec activate(t()) :: :ok | {:error, term()}
  def activate(ws), do: setopts(ws, active: :once)

  @doc "Hands the socket over to another process, which becomes its owner."
  @spec controlling_process(t(), pid()) :: :ok | {:error, term()}
  def controlling_process(%{transport: transport, socket: socket}, pid),
    do: transport.controlling_process(socket, pid)

  @doc """
  Processes a message received by the owner.

  Returns `:unknown` for messages that don't belong to this socket.
  """
  @spec stream(t(), term()) :: {:ok, t(), [frame()]} | {:error, t(), term()} | :unknown
  def stream(%__MODULE__{socket: socket} = ws, {tag, socket, data}) when tag in [:ssl, :tcp] do
    with {:ok, ws, frames} <- decode_frames(%{ws | buffer: ws.buffer <> data}, []),
         :ok <- activate(ws) do
      {:ok, ws, frames}
    else
      {:error, %__MODULE__{} = ws, reason} -> {:error, ws, reason}
      {:error, reason} -> {:error, ws, reason}
    end
  end

  def stream(%__MODULE__{socket: socket} = ws, {tag, socket})
      when tag in [:ssl_closed, :tcp_closed],
      do: {:error, ws, :closed}

  def stream(%__MODULE__{socket: socket} = ws, {tag, socket, reason})
      when tag in [:ssl_error, :tcp_error],
      do: {:error, ws, reason}

  def stream(%__MODULE__{}, _message), do: :unknown

  @doc "Sends a single, masked frame."
  @spec send_frame(t(), frame()) :: :ok | {:error, term()}
  def send_frame(ws, {:close, code, reason}) when byte_size(reason) <= 123,
    do: send_raw(ws, :close, <<code::16, reason::binary>>)

  def send_frame(ws, {opcode, payload}) when opcode in [:text, :binary, :ping, :pong],
    do: send_raw(ws, opcode, payload)

  @doc """
  Closes the socket without a closing handshake.

  Send a close frame first to close cleanly.
  """
  @spec close(t()) :: :ok
  def close(%{transport: transport, socket: socket}) do
    transport.close(socket)
    :ok
  end

  ## Connecting

  defp parse_url(url) do
    case URI.parse(url) do
      %URI{scheme: "wss", host: host} = uri when is_binary(host) and host != "" ->
        {:ok, :ssl, uri}

      %URI{scheme: "ws", host: host} = uri when is_binary(host) and host != "" ->
        {:ok, :gen_tcp, uri}

      _ ->
        {:error, {:invalid_url, url}}
    end
  end

  defp open(transport, %URI{host: host, port: port}, timeout) do
    options = [:binary, active: false, packet: :raw, nodelay: true]
    options = if transport == :ssl, do: options ++ Lingo.TLS.client_options(), else: options

    transport.connect(String.to_charlist(host), port, options, timeout)
  end

  defp handshake(ws, uri, deadline) do
    key = Base.encode64(:crypto.strong_rand_bytes(16))

    request = [
      "GET #{request_target(uri)} HTTP/1.1\r\n",
      "host: #{host_header(uri)}\r\n",
      "upgrade: websocket\r\n",
      "connection: Upgrade\r\n",
      "sec-websocket-key: #{key}\r\n",
      "sec-websocket-version: 13\r\n",
      "\r\n"
    ]

    with :ok <- ws.transport.send(ws.socket, request),
         {:ok, status, headers} <- read_response(ws, deadline),
         :ok <- validate_response(status, headers, key) do
      # anything the server sent after the headers stays in the socket buffer,
      # so the first frames arrive as regular messages once activated
      setopts(ws, packet: :raw, packet_size: 0)
    end
  end

  defp request_target(%URI{path: path, query: query}) do
    path = if path in [nil, ""], do: "/", else: path
    if query, do: path <> "?" <> query, else: path
  end

  defp host_header(%URI{scheme: "wss", host: host, port: 443}), do: host
  defp host_header(%URI{scheme: "ws", host: host, port: 80}), do: host
  defp host_header(%URI{host: host, port: port}), do: "#{host}:#{port}"

  # The VM parses HTTP for us: in `http_bin` mode every recv returns one parsed
  # line, and `packet_size` caps how long a line may be.
  defp read_response(ws, deadline) do
    with :ok <- setopts(ws, packet: :http_bin, packet_size: @max_line_length),
         {:ok, {:http_response, _version, status, _reason}} <- recv(ws, deadline),
         :ok <- setopts(ws, packet: :httph_bin),
         {:ok, headers} <- read_headers(ws, deadline, []) do
      {:ok, status, headers}
    else
      {:ok, unexpected} -> {:error, {:invalid_response, unexpected}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_headers(_ws, _deadline, headers) when length(headers) > @max_headers,
    do: {:error, :too_many_headers}

  defp read_headers(ws, deadline, headers) do
    case recv(ws, deadline) do
      {:ok, {:http_header, _, name, _, value}} ->
        name = name |> to_string() |> String.downcase()
        read_headers(ws, deadline, [{name, value} | headers])

      {:ok, :http_eoh} ->
        {:ok, headers}

      {:ok, unexpected} ->
        {:error, {:invalid_response, unexpected}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_response(101, headers, key) do
    expected_accept = Base.encode64(:crypto.hash(:sha, key <> @guid))

    cond do
      not header_has_token?(headers, "upgrade", "websocket") ->
        {:error, :invalid_upgrade_header}

      not header_has_token?(headers, "connection", "upgrade") ->
        {:error, :invalid_connection_header}

      header(headers, "sec-websocket-accept") != expected_accept ->
        {:error, :invalid_accept}

      # we offered no extensions or subprotocols, so the server may not pick any
      header(headers, "sec-websocket-extensions") ->
        {:error, :unexpected_extension}

      header(headers, "sec-websocket-protocol") ->
        {:error, :unexpected_protocol}

      true ->
        :ok
    end
  end

  defp validate_response(status, _headers, _key), do: {:error, {:unexpected_status, status}}

  defp header(headers, name) do
    case List.keyfind(headers, name, 0) do
      {_name, value} -> value
      nil -> nil
    end
  end

  defp header_has_token?(headers, name, token) do
    headers
    |> Enum.filter(fn {key, _value} -> key == name end)
    |> Enum.flat_map(fn {_key, value} -> String.split(value, ",") end)
    |> Enum.any?(&(&1 |> String.trim() |> String.downcase() == token))
  end

  ## Receiving

  defp decode_frames(ws, acc) do
    case Frame.decode(ws.buffer, max_size: ws.max_frame_size) do
      :more ->
        {:ok, ws, Enum.reverse(acc)}

      {:ok, frame, rest} ->
        case handle_frame(%{ws | buffer: rest}, frame) do
          {:ok, ws} -> decode_frames(ws, acc)
          {:ok, ws, message} -> decode_frames(ws, [message | acc])
          {:error, reason} -> {:error, ws, reason}
        end

      {:error, reason} ->
        {:error, ws, reason}
    end
  end

  defp handle_frame(ws, {:ping, true, payload}) do
    with :ok <- send_frame(ws, {:pong, payload}), do: {:ok, ws}
  end

  defp handle_frame(ws, {:pong, true, _payload}), do: {:ok, ws}

  defp handle_frame(ws, {:close, true, payload}) do
    with {:ok, code, reason} <- parse_close(payload), do: {:ok, ws, {:close, code, reason}}
  end

  # a complete, unfragmented message
  defp handle_frame(%{fragment: nil} = ws, {opcode, true, payload})
       when opcode in [:text, :binary] do
    with {:ok, message} <- message(opcode, payload), do: {:ok, ws, message}
  end

  # the first fragment of a message
  defp handle_frame(%{fragment: nil} = ws, {opcode, false, payload})
       when opcode in [:text, :binary],
       do: {:ok, %{ws | fragment: {opcode, payload, byte_size(payload)}}}

  defp handle_frame(%{fragment: {opcode, acc, size}} = ws, {:continuation, fin, payload}) do
    size = size + byte_size(payload)

    cond do
      size > ws.max_frame_size ->
        {:error, :message_too_large}

      fin ->
        with {:ok, message} <- message(opcode, IO.iodata_to_binary([acc, payload])),
             do: {:ok, %{ws | fragment: nil}, message}

      true ->
        {:ok, %{ws | fragment: {opcode, [acc, payload], size}}}
    end
  end

  defp handle_frame(%{fragment: nil}, {:continuation, _fin, _payload}),
    do: {:error, :unexpected_continuation}

  defp handle_frame(_ws, {_opcode, _fin, _payload}), do: {:error, :interleaved_message}

  defp message(:text, payload) do
    if String.valid?(payload), do: {:ok, {:text, payload}}, else: {:error, :invalid_utf8}
  end

  defp message(:binary, payload), do: {:ok, {:binary, payload}}

  # 1005 is reserved to stand for "no status code was sent"
  defp parse_close(<<>>), do: {:ok, 1005, ""}

  defp parse_close(<<code::16, reason::binary>>) do
    cond do
      not valid_close_code?(code) -> {:error, :invalid_close_code}
      not String.valid?(reason) -> {:error, :invalid_utf8}
      true -> {:ok, code, reason}
    end
  end

  defp parse_close(_payload), do: {:error, :invalid_close_payload}

  # codes defined by the RFC and IANA, plus the ranges left to libraries and
  # applications; 1004-1006 are reserved and must never appear on the wire
  defp valid_close_code?(code), do: code in 1000..1003 or code in 1007..1014 or code in 3000..4999

  ## Socket helpers

  defp send_raw(ws, opcode, payload) do
    ws.transport.send(
      ws.socket,
      Frame.encode(opcode, payload, mask: :crypto.strong_rand_bytes(4))
    )
  end

  defp recv(ws, deadline), do: ws.transport.recv(ws.socket, 0, remaining(deadline))

  defp setopts(%{transport: :ssl, socket: socket}, opts), do: :ssl.setopts(socket, opts)
  defp setopts(%{transport: :gen_tcp, socket: socket}, opts), do: :inet.setopts(socket, opts)

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
