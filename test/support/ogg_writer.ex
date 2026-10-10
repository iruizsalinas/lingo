defmodule Lingo.Test.OggWriter do
  @moduledoc false

  # Writes Ogg Opus with pages of at most `page_size` body bytes, so packets
  # span pages the way libogg-based encoders (opusenc) lay them out and
  # ffmpeg never does. ffprobe reads its output (see the voice tests).

  alias Lingo.Voice.Opus

  def file(head, packets, opts \\ []) do
    page_size = Keyword.get(opts, :page_size, 4096)
    serial = Keyword.get(opts, :serial, 1)

    audio =
      packets
      |> Enum.scan({nil, 0}, fn packet, {_previous, granule} ->
        {packet, granule + Opus.samples(packet)}
      end)
      |> Enum.flat_map(fn {packet, granule} -> segments(packet, granule) end)
      |> paginate(page_size)

    tags = Keyword.get(opts, :tags, <<"OpusTags", 5::32-little, "lingo", 0::32>>)

    ([{segments(head, 0), false, 0} | paginate(segments(tags, 0), page_size)] ++ audio)
    |> Enum.with_index()
    |> Enum.map_join(fn {{segments, continued?, granule}, sequence} ->
      flags = if(continued?, do: 1, else: 0) + if(sequence == 0, do: 2, else: 0)
      page(segments, flags, granule, serial, sequence)
    end)
  end

  # {data, lacing value, granule if the packet ends here}
  defp segments(packet, granule) do
    chunks = for <<chunk::binary-255 <- packet>>, do: {chunk, 255, nil}
    tail = binary_part(packet, div(byte_size(packet), 255) * 255, rem(byte_size(packet), 255))
    chunks ++ [{tail, byte_size(tail), granule}]
  end

  defp paginate(segments, page_size) do
    segments
    |> Enum.chunk_while(
      {[], 0},
      fn {data, _lacing, _granule} = segment, {page, size} ->
        if page != [] and (length(page) == 255 or size + byte_size(data) > page_size),
          do: {:cont, Enum.reverse(page), {[segment], byte_size(data)}},
          else: {:cont, {[segment | page], size + byte_size(data)}}
      end,
      fn {page, _size} -> {:cont, Enum.reverse(page), nil} end
    )
    |> Enum.map_reduce(false, fn page, continued? ->
      {_data, last_lacing, _granule} = List.last(page)
      granule = page |> Enum.map(&elem(&1, 2)) |> Enum.reject(&is_nil/1) |> List.last(-1)
      {{page, continued?, granule}, last_lacing == 255}
    end)
    |> elem(0)
  end

  defp page(segments, flags, granule, serial, sequence) do
    lacing = for {_data, value, _granule} <- segments, into: <<>>, do: <<value>>
    body = Enum.map_join(segments, &elem(&1, 0))

    head =
      <<"OggS", 0, flags, granule::64-signed-little, serial::32-little, sequence::32-little>>

    tail = <<byte_size(lacing)>> <> lacing <> body
    head <> <<Lingo.Voice.Ogg.Page.crc([head, <<0::32>>, tail])::32-little>> <> tail
  end
end
