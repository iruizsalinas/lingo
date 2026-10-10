defmodule Lingo.Gateway.WebSocket.Handshake do
  @moduledoc false

  # The opening handshake: TCP or TLS, then the HTTP upgrade (RFC 6455 4.1).

  alias Lingo.Gateway.WebSocket

  @guid "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  @max_headers 100
  @max_line_length 8_192

  def parse_url(url) do
    case URI.parse(url) do
      %URI{scheme: "wss", host: host} = uri when is_binary(host) and host != "" ->
        {:ok, :ssl, uri}

      %URI{scheme: "ws", host: host} = uri when is_binary(host) and host != "" ->
        {:ok, :gen_tcp, uri}

      _ ->
        {:error, {:invalid_url, url}}
    end
  end

  def open(transport, %URI{host: host, port: port}, timeout) do
    options = [:binary, active: false, packet: :raw, nodelay: true]
    options = if transport == :ssl, do: options ++ Lingo.TLS.client_options(), else: options

    transport.connect(String.to_charlist(host), port, options, timeout)
  end

  def run(ws, uri, deadline) do
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
      WebSocket.setopts(ws, packet: :raw, packet_size: 0)
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
    with :ok <- WebSocket.setopts(ws, packet: :http_bin, packet_size: @max_line_length),
         {:ok, {:http_response, _version, status, _reason}} <- recv(ws, deadline),
         :ok <- WebSocket.setopts(ws, packet: :httph_bin),
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

  defp recv(ws, deadline), do: ws.transport.recv(ws.socket, 0, remaining(deadline))
  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
