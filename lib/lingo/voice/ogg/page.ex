defmodule Lingo.Voice.Ogg.Page do
  @moduledoc false

  # Finding Ogg pages in a buffer and splitting them into segments (RFC 3533).

  import Bitwise

  @crc_table (for i <- 0..255 do
                Enum.reduce(1..8, i <<< 24, fn _bit, crc ->
                  if (crc &&& 0x80000000) != 0,
                    do: bxor(crc <<< 1, 0x04C11DB7) &&& 0xFFFFFFFF,
                    else: crc <<< 1 &&& 0xFFFFFFFF
                end)
              end)
             |> List.to_tuple()

  def next_page(
        <<"OggS", 0, header_type, _granule::64, serial::32-little, _sequence::32, crc::32-little,
          count, rest::binary>> = buffer
      ) do
    with <<lacing::binary-size(^count), body::binary>> <- rest,
         body_size = lacing |> :binary.bin_to_list() |> Enum.sum(),
         <<data::binary-size(^body_size), rest::binary>> <- body do
      page_size = 27 + count + body_size

      <<head::binary-22, _crc::32, tail::binary-size(^page_size - 26)>> =
        binary_part(buffer, 0, page_size)

      if crc([head, <<0::32>>, tail]) == crc do
        segments = split_segments(:binary.bin_to_list(lacing), data, [])
        {:page, %{serial: serial, continued?: (header_type &&& 1) == 1, segments: segments}, rest}
      else
        {:skip, binary_part(buffer, 4, byte_size(buffer) - 4)}
      end
    else
      _incomplete -> :more
    end
  end

  def next_page(<<"OggS", _::binary>> = buffer) when byte_size(buffer) < 27, do: :more

  # an unknown version: not a page we can read
  def next_page(<<"OggS", rest::binary>>), do: {:skip, rest}

  # resynchronise on the next capture pattern
  def next_page(buffer) do
    case :binary.match(buffer, "OggS") do
      {position, _length} -> {:skip, binary_part(buffer, position, byte_size(buffer) - position)}
      :nomatch when byte_size(buffer) > 3 -> {:skip, binary_part(buffer, byte_size(buffer), -3)}
      :nomatch -> :more
    end
  end

  # lacing values of 255 continue a packet, anything less ends it
  def split_segments([], _data, segments), do: Enum.reverse(segments)

  def split_segments(lacing, data, segments) do
    {run, rest} = Enum.split_while(lacing, &(&1 == 255))

    {sizes, lacing, complete?} =
      case rest do
        [last | lacing] -> {run ++ [last], lacing, true}
        [] -> {run, [], false}
      end

    size = Enum.sum(sizes)
    <<segment::binary-size(^size), data::binary>> = data
    split_segments(lacing, data, [{segment, complete?} | segments])
  end

  @doc false
  @spec crc(iodata()) :: non_neg_integer()
  def crc(data) do
    for <<byte <- IO.iodata_to_binary(data)>>, reduce: 0 do
      crc -> bxor(crc <<< 8 &&& 0xFFFFFFFF, elem(@crc_table, bxor(crc >>> 24, byte)))
    end
  end
end
