defmodule Lingo.Test.WebMWriter do
  @moduledoc false

  # Writes minimal Matroska audio, enough to test the WebM reader with what
  # ffmpeg never produces: laced blocks of every kind, BlockGroups, other
  # tracks, unknown sizes. ffprobe reads its output (see the voice tests).

  @doc """
  An Opus file. `blocks` is a list of `{lacing, packets}` (lacing is `:none`,
  `:xiph`, `:fixed` or `:ebml`) or `{:other_track, data}` for a block of track 2, a subtitle track.
  """
  def file(head, blocks, opts \\ []) do
    cluster =
      [element(0xE7, <<0>>) | Enum.map(blocks, &block(&1, opts))]
      |> IO.iodata_to_binary()

    segment =
      element(0x1654AE6B, [track(1, 2, "A_OPUS", head), track(2, 0x11, "S_TEXT/UTF8", "")]) <>
        container(0x1F43B675, cluster, opts[:unknown_sizes])

    element(0x1A45DFA3, element(0x4282, "webm")) <>
      container(0x18538067, segment, opts[:unknown_sizes])
  end

  defp track(number, type, codec, private) do
    element(0xAE, [
      element(0xD7, <<number>>),
      element(0x83, <<type>>),
      element(0x86, codec),
      element(0x63A2, private)
    ])
  end

  defp block({:other_track, data}, _opts), do: element(0xA3, [<<0x82, 0::16, 0x80>>, data])

  defp block({lacing, packets}, opts) do
    body = [<<0x81, 0::16>> | lace(lacing, packets)]
    if opts[:block_groups], do: element(0xA0, element(0xA1, body)), else: element(0xA3, body)
  end

  defp lace(:none, [packet]), do: [<<0x80>>, packet]
  defp lace(:xiph, packets), do: [<<0x82, length(packets) - 1>>, xiph_sizes(packets), packets]
  defp lace(:fixed, packets), do: [<<0x84, length(packets) - 1>>, packets]
  defp lace(:ebml, packets), do: [<<0x86, length(packets) - 1>>, ebml_sizes(packets), packets]

  defp xiph_sizes(packets) do
    for packet <- Enum.drop(packets, -1),
        do: [List.duplicate(255, div(byte_size(packet), 255)), rem(byte_size(packet), 255)]
  end

  # the first size as a 4-byte vint, then 2-byte signed differences
  defp ebml_sizes(packets) do
    sizes = packets |> Enum.map(&byte_size/1) |> Enum.drop(-1)

    differences =
      sizes
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [previous, size] -> <<1::2, size - previous + 8191::14>> end)

    [<<1::4, hd(sizes)::28>> | differences]
  end

  defp container(id, body, true),
    do: [id_bytes(id), <<0x01, -1::56>>, body] |> IO.iodata_to_binary()

  defp container(id, body, _sized), do: element(id, body)

  def element(id, body) do
    body = IO.iodata_to_binary(body)
    id_bytes(id) <> <<0x01, byte_size(body)::56>> <> body
  end

  defp id_bytes(id), do: :binary.encode_unsigned(id)
end
