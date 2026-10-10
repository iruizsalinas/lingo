defmodule Lingo.Voice.Dave.Frame.Ranges do
  @moduledoc false

  # Unencrypted ranges: the offset/size pairs of a frame that stay in the clear
  # and are authenticated as AAD.

  alias Lingo.Voice.Dave.Frame

  # splits a frame into the concatenated unencrypted ranges and the rest
  def split(frame, ranges) do
    {aad, plaintext, offset} =
      Enum.reduce(ranges, {[], [], 0}, fn {start, size}, {aad, plaintext, offset} ->
        {[aad, binary_part(frame, start, size)],
         [plaintext, binary_part(frame, offset, start - offset)], start + size}
      end)

    plaintext = [plaintext, binary_part(frame, offset, byte_size(frame) - offset)]
    {IO.iodata_to_binary(aad), IO.iodata_to_binary(plaintext)}
  end

  # the inverse of split/2: puts the unencrypted ranges back in place
  def interleave(encrypted, _aad, [], _size), do: encrypted

  def interleave(encrypted, aad, ranges, size) do
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

  def encode_ranges(ranges),
    do: Enum.map(ranges, fn {offset, size} -> [Frame.uleb128(offset), Frame.uleb128(size)] end)

  def decode_ranges(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  def decode_ranges(binary, acc) do
    with {:ok, offset, rest} <- Frame.decode_uleb128(binary),
         {:ok, size, rest} <- Frame.decode_uleb128(rest) do
      decode_ranges(rest, [{offset, size} | acc])
    end
  end

  # ascending, non-overlapping and inside the frame
  def valid_ranges?(ranges, body_size) do
    Enum.reduce_while(ranges, 0, fn {offset, size}, minimum ->
      if offset >= minimum and offset + size <= body_size,
        do: {:cont, offset + size},
        else: {:halt, false}
    end) != false
  end
end
