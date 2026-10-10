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

  alias Lingo.Gateway.WebSocket.Handshake

  @timeout 10_000
  @max_frame_size 64 * 1024 * 1024

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

    with {:ok, transport, uri} <- Handshake.parse_url(url),
         {:ok, socket} <- Handshake.open(transport, uri, remaining(deadline)) do
      ws = %__MODULE__{
        transport: transport,
        socket: socket,
        max_frame_size: Keyword.get(opts, :max_frame_size, @max_frame_size)
      }

      case Handshake.run(ws, uri, deadline) do
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

  @doc false
  def setopts(%{transport: :ssl, socket: socket}, opts), do: :ssl.setopts(socket, opts)
  def setopts(%{transport: :gen_tcp, socket: socket}, opts), do: :inet.setopts(socket, opts)

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
