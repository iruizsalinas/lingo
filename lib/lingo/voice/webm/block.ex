defmodule Lingo.Voice.WebM.Block do
  @moduledoc false

  # The frames in a Matroska block, unlaced (RFC 9559, section 10).

  import Bitwise
  alias Lingo.Voice.WebM.EBML

  def frames(block) do
    {:ok, _track, <<_timecode::16, flags, data::binary>>} = EBML.decode_vint(block)

    case flags >>> 1 &&& 3 do
      0 -> [data]
      lacing -> laced(lacing, data)
    end
  rescue
    # a damaged block is dropped, as a page with a bad checksum is in Ogg
    _malformed in [MatchError, FunctionClauseError] -> []
  end

  # lacing packs several frames in one block; the last frame's size is what's left
  def laced(lacing, <<count_minus_one, data::binary>>) do
    {sizes, data} =
      case lacing do
        1 -> xiph_sizes(count_minus_one, data)
        2 -> {List.duplicate(div(byte_size(data), count_minus_one + 1), count_minus_one), data}
        3 -> ebml_sizes(count_minus_one, data)
      end

    {frames, last} =
      Enum.map_reduce(sizes, data, fn size, data ->
        <<frame::binary-size(^size), rest::binary>> = data
        {frame, rest}
      end)

    frames ++ [last]
  end

  # each size is a run of 255s plus the byte that ends it
  def xiph_sizes(count, data) do
    Enum.map_reduce(1..count//1, data, fn _index, data -> xiph_size(data, 0) end)
  end

  def xiph_size(<<255, rest::binary>>, sum), do: xiph_size(rest, sum + 255)
  def xiph_size(<<byte, rest::binary>>, sum), do: {sum + byte, rest}

  # the first size, then each one as a signed difference from the one before
  def ebml_sizes(0, data), do: {[], data}

  def ebml_sizes(count, data) do
    {:ok, first, data} = EBML.decode_vint(data)

    {sizes, data} =
      Enum.reduce(2..count//1, {[first], data}, fn _, {[previous | _] = sizes, data} ->
        {:ok, raw, length, data} = EBML.decode_vint_with_length(data)
        {[previous + raw - ((1 <<< (7 * length - 1)) - 1) | sizes], data}
      end)

    {Enum.reverse(sizes), data}
  end
end
