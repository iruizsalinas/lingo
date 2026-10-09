defmodule Lingo.Voice.Dave.Frame do
  @moduledoc false

  # The DAVE end-to-end encrypted media frame (DAVE protocol, "Media Frame
  # Encryption"), as libdave lays it out:
  #
  #   interleaved frame | 8 byte tag | ULEB128 nonce | ULEB128 ranges | size | 0xFAFA
  #
  # `size` counts every byte after the interleaved frame. Unencrypted ranges
  # (offset/size pairs into the frame) are authenticated as AAD; Opus frames
  # have none. The 32 bit nonce expands to 8 zero bytes followed by the nonce
  # in little-endian order, which is how libdave copies it in memory.

  import Bitwise

  @marker <<0xFA, 0xFA>>
  @tag_size 8
  @min_supplemental_size @tag_size + 1 + 2
  @silence <<0xF8, 0xFF, 0xFE>>

  @type range :: {offset :: non_neg_integer(), size :: non_neg_integer()}
  @type parsed :: %{
          nonce: non_neg_integer(),
          tag: binary(),
          aad: binary(),
          ciphertext: binary(),
          ranges: [range()],
          body_size: non_neg_integer()
        }

  @doc "The Opus silence frame, which DAVE passes through unencrypted."
  def silence, do: @silence

  @spec encrypt(binary(), binary(), non_neg_integer(), [range()]) :: binary()
  def encrypt(frame, key, nonce, ranges \\ []) do
    {aad, plaintext} = split(frame, ranges)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(
        :aes_128_gcm,
        key,
        full_nonce(nonce),
        plaintext,
        aad,
        @tag_size,
        true
      )

    supplemental = [tag, uleb128(nonce), encode_ranges(ranges)]
    size = IO.iodata_length(supplemental) + 3

    IO.iodata_to_binary([
      interleave(ciphertext, aad, ranges, byte_size(frame)),
      supplemental,
      size,
      @marker
    ])
  end

  @doc "Parses a protocol frame; anything else is not an encrypted DAVE frame."
  @spec parse(binary()) :: {:ok, parsed()} | :error
  def parse(frame) when byte_size(frame) >= @min_supplemental_size do
    frame_size = byte_size(frame)
    size = :binary.at(frame, frame_size - 3)
    body_size = frame_size - size

    with @marker <- binary_part(frame, frame_size, -2),
         true <- size >= @min_supplemental_size and size <= frame_size,
         <<body::binary-size(^body_size), tag::binary-size(@tag_size), rest::binary>> <- frame,
         {:ok, nonce, rest} <- decode_uleb128(binary_part(rest, 0, byte_size(rest) - 3)),
         {:ok, ranges} <- decode_ranges(rest, []),
         true <- valid_ranges?(ranges, body_size) do
      {aad, ciphertext} = split(body, ranges)

      {:ok,
       %{
         nonce: nonce &&& 0xFFFFFFFF,
         tag: tag,
         aad: aad,
         ciphertext: ciphertext,
         ranges: ranges,
         body_size: body_size
       }}
    else
      _invalid -> :error
    end
  end

  def parse(_frame), do: :error

  @spec decrypt(parsed(), binary()) :: {:ok, binary()} | :error
  def decrypt(parsed, key) do
    case :crypto.crypto_one_time_aead(
           :aes_128_gcm,
           key,
           full_nonce(parsed.nonce),
           parsed.ciphertext,
           parsed.aad,
           parsed.tag,
           false
         ) do
      :error -> :error
      plaintext -> {:ok, interleave(plaintext, parsed.aad, parsed.ranges, parsed.body_size)}
    end
  end

  defp full_nonce(nonce), do: <<0::64, nonce::32-little>>

  ## Unencrypted ranges

  # splits a frame into the concatenated unencrypted ranges and the rest
  defp split(frame, ranges) do
    {aad, plaintext, offset} =
      Enum.reduce(ranges, {[], [], 0}, fn {start, size}, {aad, plaintext, offset} ->
        {[aad, binary_part(frame, start, size)],
         [plaintext, binary_part(frame, offset, start - offset)], start + size}
      end)

    plaintext = [plaintext, binary_part(frame, offset, byte_size(frame) - offset)]
    {IO.iodata_to_binary(aad), IO.iodata_to_binary(plaintext)}
  end

  # the inverse of split/2: puts the unencrypted ranges back in place
  defp interleave(encrypted, _aad, [], _size), do: encrypted

  defp interleave(encrypted, aad, ranges, size) do
    {parts, encrypted, aad, offset} =
      Enum.reduce(ranges, {[], encrypted, aad, 0}, fn {start, range_size},
                                                      {parts, encrypted, aad, offset} ->
        gap = start - offset
        <<before::binary-size(^gap), encrypted::binary>> = encrypted
        <<plain::binary-size(^range_size), aad::binary>> = aad
        {[parts, before, plain], encrypted, aad, start + range_size}
      end)

    <<>> = aad
    ^size = offset + byte_size(encrypted)
    IO.iodata_to_binary([parts, encrypted])
  end

  defp encode_ranges(ranges),
    do: Enum.map(ranges, fn {offset, size} -> [uleb128(offset), uleb128(size)] end)

  defp decode_ranges(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp decode_ranges(binary, acc) do
    with {:ok, offset, rest} <- decode_uleb128(binary),
         {:ok, size, rest} <- decode_uleb128(rest) do
      decode_ranges(rest, [{offset, size} | acc])
    end
  end

  # ascending, non-overlapping and inside the frame
  defp valid_ranges?(ranges, body_size) do
    Enum.reduce_while(ranges, 0, fn {offset, size}, minimum ->
      if offset >= minimum and offset + size <= body_size,
        do: {:cont, offset + size},
        else: {:halt, false}
    end) != false
  end

  ## ULEB128

  @spec uleb128(non_neg_integer()) :: binary()
  def uleb128(value) when value < 0x80, do: <<value>>
  def uleb128(value), do: <<0x80 ||| (value &&& 0x7F)>> <> uleb128(value >>> 7)

  @spec decode_uleb128(binary()) :: {:ok, non_neg_integer(), binary()} | :error
  def decode_uleb128(binary), do: decode_uleb128(binary, 0, 0)

  # at most 10 bytes, enough for 64 bits
  defp decode_uleb128(_binary, shift, _value) when shift >= 70, do: :error

  defp decode_uleb128(<<0::1, byte::7, rest::binary>>, shift, value),
    do: {:ok, value ||| byte <<< shift, rest}

  defp decode_uleb128(<<1::1, byte::7, rest::binary>>, shift, value),
    do: decode_uleb128(rest, shift + 7, value ||| byte <<< shift)

  defp decode_uleb128(<<>>, _shift, _value), do: :error
end
