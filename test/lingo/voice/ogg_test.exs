defmodule Lingo.Voice.OggTest do
  use ExUnit.Case, async: true

  alias Lingo.Voice.{FFmpeg, Ogg, Player}

  # a minimal Ogg writer: one page per list of {segment, complete?}
  defp page(segments, opts \\ []) do
    lacing =
      Enum.flat_map(segments, fn {data, complete?} ->
        full = List.duplicate(255, div(byte_size(data), 255))
        if complete?, do: full ++ [rem(byte_size(data), 255)], else: full
      end)

    header_type = if opts[:continued], do: 1, else: 0
    body = Enum.map_join(segments, &elem(&1, 0))
    serial = Keyword.get(opts, :serial, 7)

    head = <<"OggS", 0, header_type, 0::64, serial::32-little, 0::32>>
    tail = [length(lacing) | lacing] |> :binary.list_to_bin() |> Kernel.<>(body)
    crc = Lingo.Voice.Ogg.Page.crc([head, <<0::32>>, tail])
    head <> <<crc::32-little>> <> tail
  end

  defp packets(chunks), do: chunks |> Ogg.packets() |> Enum.to_list()

  test "reads packets and skips the Opus headers" do
    data =
      page([{<<"OpusHead", 1, 2, 0::64, 0>>, true}]) <>
        page([{"OpusTags", true}]) <>
        page([{"one", true}, {"two", true}])

    assert packets([data]) == ["one", "two"]
  end

  test "reassembles packets spanning pages and lacing runs, from any chunking" do
    big = :binary.copy("x", 600)

    data =
      page([{binary_part(big, 0, 510), false}]) <>
        page([{binary_part(big, 510, 90), true}], continued: true)

    assert packets([data]) == [big]

    # byte by byte
    assert packets(for <<byte <- data>>, do: <<byte>>) == [big]
  end

  test "skips pages with a bad checksum and resynchronises on garbage" do
    good = page([{"good", true}])
    <<head::binary-22, _crc::32, tail::binary>> = page([{"bad", true}])
    corrupted = head <> <<0::32>> <> tail

    assert packets(["junk", corrupted, good]) == ["good"]
  end

  test "ignores other logical streams" do
    data =
      page([{"mine", true}]) <> page([{"other", true}], serial: 9) <> page([{"mine too", true}])

    assert packets([data]) == ["mine", "mine too"]
  end

  test "reads a file lazily" do
    path = Path.join(System.tmp_dir!(), "lingo-ogg-#{System.unique_integer([:positive])}.opus")

    File.write!(
      path,
      page([{<<"OpusHead", 1, 2, 0::64, 0>>, true}]) <>
        page([{"OpusTags", true}]) <> page([{"a", true}, {"b", true}])
    )

    on_exit(fn -> File.rm(path) end)

    assert Enum.to_list(Ogg.stream!(path)) == ["a", "b"]
  end

  test "ffmpeg is asked for 48 kHz stereo Opus in Ogg on stdout" do
    args = FFmpeg.args("song.mp3", bitrate: 96_000)

    assert ["-hide_banner", "-loglevel", "error", "-nostdin", "-i", "song.mp3" | _] = args
    assert Enum.chunk_every(args, 2, 1) |> Enum.member?(["-b:a", "96000"])
    assert List.last(args) == "pipe:1"
  end

  test "the player paces packets and ends with silence" do
    packets = for n <- 1..5, do: <<0xFC, n>>
    start = System.monotonic_time(:millisecond)
    {:ok, player} = Player.start_link(self(), packets)

    for n <- 1..5, do: assert_receive({:player_frame, ^player, <<0xFC, ^n>>}, 1_000)
    for _ <- 1..5, do: assert_receive({:player_frame, ^player, <<0xF8, 0xFF, 0xFE>>}, 1_000)
    assert_receive {:player_done, ^player}, 1_000

    # ten 20 ms frames: the last one goes out about 180 ms in
    assert System.monotonic_time(:millisecond) - start >= 170
  end

  test "the player picks up the beat after a stalled source instead of bursting" do
    stall = Stream.map([:stall], fn _ -> Process.sleep(300) && <<0xFC, 0>> end)
    packets = Stream.concat([stall, for(n <- 1..6, do: <<0xFC, n>>)])
    {:ok, player} = Player.start_link(self(), packets)

    times =
      for n <- 0..6 do
        assert_receive {:player_frame, ^player, <<0xFC, ^n>>}, 1_000
        System.monotonic_time(:millisecond)
      end

    # the late first packet restarts the clock: the rest still come 20 ms apart
    intervals = times |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> b - a end)
    assert Enum.all?(intervals, &(&1 >= 10)), "burst: #{inspect(intervals)}"
  end
end
