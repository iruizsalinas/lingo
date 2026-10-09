defmodule Lingo.Voice.Ogg do
  @moduledoc """
  Reads Opus packets out of Ogg Opus audio (RFC 3533, RFC 7845).

  Parsing works on a stream of binary chunks, so files and pipes are read
  lazily. Pages with a bad checksum are skipped, as are the OpusHead and
  OpusTags header packets. Chained files, one track after another as radio
  streams send them, play through.
  """

  import Bitwise

  alias Lingo.Voice.Opus

  # an Opus packet holds at most 120 ms: 48 frames of 1275 bytes, and framing
  @max_packet 65_536

  @crc_table (for i <- 0..255 do
                Enum.reduce(1..8, i <<< 24, fn _bit, crc ->
                  if (crc &&& 0x80000000) != 0,
                    do: bxor(crc <<< 1, 0x04C11DB7) &&& 0xFFFFFFFF,
                    else: crc <<< 1 &&& 0xFFFFFFFF
                end)
              end)
             |> List.to_tuple()

  @doc "Streams the Opus packets of an Ogg Opus file."
  @spec stream!(Path.t()) :: Enumerable.t()
  def stream!(path), do: path |> File.stream!(65_536) |> packets()

  @doc "Turns a stream of Ogg data chunks into a stream of Opus packets."
  @spec packets(Enumerable.t()) :: Enumerable.t()
  def packets(chunks) do
    Stream.transform(
      chunks,
      %{buffer: <<>>, partial: {[], 0}, serial: nil, tags?: false},
      &parse/2
    )
  end

  defp parse(chunk, state), do: read_pages(%{state | buffer: state.buffer <> chunk}, [])

  defp read_pages(state, packets) do
    case next_page(state.buffer) do
      {:page, page, rest} ->
        {state, packets} = collect(%{state | buffer: rest}, page, packets)
        read_pages(state, packets)

      {:skip, rest} ->
        read_pages(%{state | buffer: rest}, packets)

      :more ->
        {Enum.reverse(packets), state}
    end
  end

  # An OpusHead starts an Opus stream and makes it the one we read. That's how
  # chained files (one track after another, as radio streams do) and files
  # with other codecs alongside work. The OpusTags packet after it is skipped.
  defp collect(
         state,
         %{continued?: false, segments: [{<<"OpusHead", _::binary>> = head, true} | _]} = page,
         packets
       ) do
    case Opus.check_head(head) do
      :ok -> {%{state | serial: page.serial, partial: {[], 0}, tags?: true}, packets}
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  # pages of any other logical stream are ignored
  defp collect(%{serial: serial} = state, %{serial: page_serial}, packets)
       when serial != nil and serial != page_serial,
       do: {state, packets}

  defp collect(state, page, packets) do
    partial =
      cond do
        not page.continued? -> {[], 0}
        state.partial != {[], 0} -> state.partial
        # the rest of a packet whose beginning we never saw (we started mid-stream)
        true -> :drop
      end

    {partial, tags?, packets} =
      Enum.reduce(page.segments, {partial, state.tags?, packets}, &segment/2)

    {%{state | partial: partial, serial: page.serial, tags?: tags?}, packets}
  end

  # the OpusTags packet, cover art and all, is dropped as it goes by
  defp segment({_data, complete?}, {_partial, true, packets}),
    do: {{[], 0}, not complete?, packets}

  defp segment({_data, complete?}, {:drop, false, packets}),
    do: {if(complete?, do: {[], 0}, else: :drop), false, packets}

  defp segment({data, true}, {{partial, _size}, false, packets}),
    do: {{[], 0}, false, [IO.iodata_to_binary([partial, data]) | packets]}

  defp segment({data, false}, {{partial, size}, false, packets}) do
    size = size + byte_size(data)

    if size > @max_packet,
      do: raise(ArgumentError, "an Ogg packet is larger than #{@max_packet} bytes")

    {{[partial, data], size}, false, packets}
  end

  defp next_page(
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

  defp next_page(<<"OggS", _::binary>> = buffer) when byte_size(buffer) < 27, do: :more

  # an unknown version: not a page we can read
  defp next_page(<<"OggS", rest::binary>>), do: {:skip, rest}

  # resynchronise on the next capture pattern
  defp next_page(buffer) do
    case :binary.match(buffer, "OggS") do
      {position, _length} -> {:skip, binary_part(buffer, position, byte_size(buffer) - position)}
      :nomatch when byte_size(buffer) > 3 -> {:skip, binary_part(buffer, byte_size(buffer), -3)}
      :nomatch -> :more
    end
  end

  # lacing values of 255 continue a packet, anything less ends it
  defp split_segments([], _data, segments), do: Enum.reverse(segments)

  defp split_segments(lacing, data, segments) do
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
