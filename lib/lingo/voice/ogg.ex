defmodule Lingo.Voice.Ogg do
  @moduledoc """
  Reads Opus packets out of Ogg Opus audio (RFC 3533, RFC 7845).

  Parsing works on a stream of binary chunks, so files and pipes are read
  lazily. Pages with a bad checksum are skipped, as are the OpusHead and
  OpusTags header packets. Chained files, one track after another as radio
  streams send them, play through.
  """

  alias Lingo.Voice.Ogg.Page

  alias Lingo.Voice.Opus

  # an Opus packet holds at most 120 ms: 48 frames of 1275 bytes, and framing
  @max_packet 65_536

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
    case Page.next_page(state.buffer) do
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
end
