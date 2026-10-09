defmodule Lingo.Gateway.WebSocket.Frame do
  @moduledoc false

  # Encodes and decodes single WebSocket frames (RFC 6455, section 5.2).
  #
  # Decoding validates everything that can be checked at the frame level and
  # never trusts a length before checking it against `:max_size`, so a peer
  # can't make us buffer more than we agreed to.

  @type opcode :: :continuation | :text | :binary | :close | :ping | :pong
  @type t :: {opcode(), fin :: boolean(), payload :: binary()}

  @opcodes %{
    0x0 => :continuation,
    0x1 => :text,
    0x2 => :binary,
    0x8 => :close,
    0x9 => :ping,
    0xA => :pong
  }
  @codes Map.new(@opcodes, fn {code, opcode} -> {opcode, code} end)

  @max_control_size 125
  @default_max_size 64 * 1024 * 1024

  @doc """
  Encodes a frame.

  Options:

    * `:mask` - a 4 byte masking key, required for frames sent by a client
    * `:fin` - whether this is the final fragment, defaults to `true`
  """
  @spec encode(opcode(), iodata(), keyword()) :: iodata()
  def encode(opcode, payload, opts \\ []) do
    payload = IO.iodata_to_binary(payload)
    fin = if Keyword.get(opts, :fin, true), do: 1, else: 0

    header = <<fin::1, 0::3, Map.fetch!(@codes, opcode)::4>>

    case Keyword.get(opts, :mask) do
      nil -> [header, encode_length(0, byte_size(payload)), payload]
      <<_::32>> = key -> [header, encode_length(1, byte_size(payload)), key, mask(payload, key)]
    end
  end

  defp encode_length(mask, length) when length <= 125, do: <<mask::1, length::7>>
  defp encode_length(mask, length) when length <= 0xFFFF, do: <<mask::1, 126::7, length::16>>
  defp encode_length(mask, length), do: <<mask::1, 127::7, length::64>>

  @doc """
  Decodes the first frame in `buffer`.

  Returns `:more` when the buffer doesn't hold a whole frame yet.

  Options:

    * `:masked` - whether frames are expected to be masked, defaults to `false`
      (true for frames sent by a client, false for frames sent by a server)
    * `:max_size` - the largest payload accepted, in bytes
  """
  @spec decode(binary(), keyword()) :: {:ok, t(), rest :: binary()} | :more | {:error, atom()}
  def decode(buffer, opts \\ [])

  def decode(<<fin::1, rsv::3, code::4, mask::1, length::7, rest::binary>>, opts) do
    masked? = mask == 1

    with {:ok, opcode} <- fetch_opcode(code),
         :ok <- check(rsv == 0, :reserved_bits_set),
         :ok <- check(masked? == Keyword.get(opts, :masked, false), :unexpected_mask),
         :ok <- check(fin == 1 or not control?(opcode), :fragmented_control_frame),
         :ok <-
           check(length <= @max_control_size or not control?(opcode), :control_frame_too_large),
         {:ok, length, rest} <- decode_length(length, rest),
         :ok <- check(length <= Keyword.get(opts, :max_size, @default_max_size), :frame_too_large),
         {:ok, payload, rest} <- decode_payload(length, masked?, rest) do
      {:ok, {opcode, fin == 1, payload}, rest}
    end
  end

  def decode(_buffer, _opts), do: :more

  defp fetch_opcode(code) do
    case Map.fetch(@opcodes, code) do
      {:ok, opcode} -> {:ok, opcode}
      :error -> {:error, :unknown_opcode}
    end
  end

  defp control?(opcode), do: opcode in [:close, :ping, :pong]

  defp decode_length(126, <<length::16, rest::binary>>), do: {:ok, length, rest}
  defp decode_length(126, _rest), do: :more
  # the most significant bit of a 64 bit length must be zero
  defp decode_length(127, <<1::1, _::63, _::binary>>), do: {:error, :invalid_length}
  defp decode_length(127, <<length::64, rest::binary>>), do: {:ok, length, rest}
  defp decode_length(127, _rest), do: :more
  defp decode_length(length, rest), do: {:ok, length, rest}

  defp decode_payload(length, masked?, rest) do
    case {masked?, rest} do
      {true, <<key::binary-4, payload::binary-size(^length), rest::binary>>} ->
        {:ok, mask(payload, key), rest}

      {false, <<payload::binary-size(^length), rest::binary>>} ->
        {:ok, payload, rest}

      _incomplete ->
        :more
    end
  end

  # masking is its own inverse: XOR with the key repeated over the payload
  defp mask(<<>>, _key), do: <<>>

  defp mask(payload, key) do
    size = byte_size(payload)
    key_stream = key |> :binary.copy(div(size, 4) + 1) |> binary_part(0, size)
    :crypto.exor(payload, key_stream)
  end

  defp check(true, _reason), do: :ok
  defp check(false, reason), do: {:error, reason}
end
