defmodule Lingo.Voice.Opus do
  @moduledoc false

  # Reads an Opus packet's duration from its TOC byte (RFC 6716, section 3.1),
  # so playback is paced and timestamped correctly whatever the frame size.

  import Bitwise

  @silk [480, 960, 1920, 2880]
  @hybrid [480, 960]
  @celt [120, 240, 480, 960]

  @doc "The number of 48 kHz samples in a packet; 20 ms for anything unreadable."
  @spec samples(binary()) :: pos_integer()
  def samples(<<toc, rest::binary>>) do
    config = toc >>> 3

    frame_size =
      cond do
        config < 12 -> Enum.at(@silk, rem(config, 4))
        config < 16 -> Enum.at(@hybrid, rem(config, 2))
        true -> Enum.at(@celt, rem(config, 4))
      end

    frames =
      case {toc &&& 3, rest} do
        {0, _} -> 1
        {code, _} when code in [1, 2] -> 2
        {3, <<count_byte, _::binary>>} -> max(count_byte &&& 0x3F, 1)
        {3, <<>>} -> 1
      end

    # a packet holds at most 120 ms
    min(frame_size * frames, 5760)
  end

  def samples(_packet), do: 960

  @doc """
  Checks an OpusHead header (RFC 7845, section 5.1) describes a single Opus
  stream, mono or stereo: the only kind Discord plays. Surround audio packs
  several streams into each packet and has to be downmixed first.
  """
  @spec check_head(binary()) :: :ok | {:error, String.t()}
  def check_head(<<"OpusHead", version, channels, _::binary-size(8), family, rest::binary>>)
      when version < 16 do
    case {family, rest} do
      {0, _} when channels in 1..2 -> :ok
      {_family, <<1, _::binary>>} when channels > 0 -> :ok
      _surround -> {:error, "#{channels}-channel Opus can't be played; downmix it to stereo"}
    end
  end

  def check_head(_head), do: {:error, "not a valid OpusHead"}
end
