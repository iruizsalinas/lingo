defmodule Lingo.Voice.ContainersTest do
  use ExUnit.Case, async: true

  # Real files from ffmpeg/libopus in test/fixtures/audio. packets.csv lists
  # every packet ffprobe reads from them (size and SHA-256), so these tests
  # check the readers against ffmpeg's own demuxers. The laced and page-spanning
  # layouts ffmpeg never writes come from Lingo.Test.WebMWriter and OggWriter,
  # whose output ffprobe reads back as the same packets.

  alias Lingo.Test.{OggWriter, WebMWriter}
  alias Lingo.Voice.{Ogg, Opus, WebM}

  @dir "test/fixtures/audio"

  @expected @dir
            |> Path.join("packets.csv")
            |> File.stream!()
            |> Enum.map(&String.split(String.trim(&1), ","))
            |> Enum.group_by(&hd/1, fn [_file, size, hash | _] ->
              {String.to_integer(size), hash}
            end)

  @head <<"OpusHead", 1, 2, 312::16-little, 48_000::32-little, 0::16, 0>>

  defp read(reader, path, chunk_size),
    do: path |> File.stream!(chunk_size) |> reader.packets() |> Enum.to_list()

  defp fingerprint(packets),
    do:
      Enum.map(
        packets,
        &{byte_size(&1), "SHA256:" <> Base.encode16(:crypto.hash(:sha256, &1), case: :lower)}
      )

  defp packets(file), do: Ogg.stream!(Path.join(@dir, file)) |> Enum.to_list()

  defp chunks(binary, size),
    do:
      for(<<chunk::binary-size(^size) <- binary>>, do: chunk) ++
        [binary_part(binary, div(byte_size(binary), size) * size, rem(byte_size(binary), size))]

  describe "matches ffprobe" do
    for {file, reader} <- [
          {"stereo_20ms.opus", Ogg},
          {"stereo_2_5ms.opus", Ogg},
          {"mono_60ms.opus", Ogg},
          {"noise_60ms.opus", Ogg},
          {"stereo.webm", WebM},
          {"live.webm", WebM}
        ] do
      test "#{file}, however the input is chunked" do
        expected = @expected[unquote(file)]
        path = Path.join(@dir, unquote(file))

        for chunk_size <- [65_536, 1_000, 7, 1] do
          assert fingerprint(read(unquote(reader), path, chunk_size)) == expected
        end
      end
    end

    test "packet durations come from the TOC byte" do
      assert packets("stereo_20ms.opus") |> Enum.map(&Opus.samples/1) |> Enum.uniq() == [960]
      assert packets("stereo_2_5ms.opus") |> Enum.map(&Opus.samples/1) |> Enum.uniq() == [120]
      assert packets("mono_60ms.opus") |> Enum.map(&Opus.samples/1) |> Enum.uniq() == [2880]
    end
  end

  describe "Ogg" do
    test "chained files play one track after another" do
      assert fingerprint(packets("chained.opus")) ==
               @expected["stereo_20ms.opus"] ++ @expected["mono_60ms.opus"]
    end

    test "packets spanning pages, as libogg-based encoders write them" do
      packets = packets("noise_60ms.opus")

      for page_size <- [100, 1_000, 4_096] do
        data = OggWriter.file(@head, packets, page_size: page_size)
        assert Ogg.packets(chunks(data, 333)) |> Enum.to_list() == packets
      end
    end

    test "starting mid-stream drops the packet whose beginning is missing" do
      packets = packets("noise_60ms.opus")
      data = OggWriter.file(@head, packets, page_size: 1_000)

      # cut into the middle of the audio pages
      position = data |> :binary.matches("OggS") |> Enum.at(5) |> elem(0)

      heard =
        Ogg.packets([binary_part(data, position, byte_size(data) - position)]) |> Enum.to_list()

      assert heard != [] and heard == Enum.take(packets, -length(heard))
    end

    test "huge OpusTags, cover art and all, are skipped" do
      packets = packets("stereo_20ms.opus")
      tags = <<"OpusTags", 0::32-little, 1::32-little>> <> :rand.bytes(300_000)
      data = OggWriter.file(@head, packets, tags: tags, page_size: 4_096)

      assert Ogg.packets(chunks(data, 4_096)) |> Enum.to_list() == packets
    end

    test "surround audio is refused rather than sent as noise" do
      assert_raise ArgumentError, ~r/6-channel Opus/, fn -> packets("surround.opus") end
    end

    test "a truncated file yields the packets before the cut" do
      packets = packets("stereo_20ms.opus")
      data = OggWriter.file(@head, packets, page_size: 1_000)
      heard = Ogg.packets([binary_part(data, 0, div(byte_size(data), 2))]) |> Enum.to_list()
      assert heard != [] and heard == Enum.take(packets, length(heard))
    end
  end

  describe "WebM" do
    setup do
      %{packets: packets("stereo_20ms.opus")}
    end

    test "every kind of lacing", %{packets: packets} do
      for lacing <- [:xiph, :ebml] do
        data = WebMWriter.file(@head, Enum.map(Enum.chunk_every(packets, 7), &{lacing, &1}))
        assert WebM.packets(chunks(data, 100)) |> Enum.to_list() == packets
      end

      equal = for n <- 1..20, do: :binary.copy(<<0xFC, n>>, 80)
      data = WebMWriter.file(@head, Enum.map(Enum.chunk_every(equal, 6), &{:fixed, &1}))
      assert WebM.packets([data]) |> Enum.to_list() == equal
    end

    test "packets of 255 bytes and more in Xiph lacing" do
      sizes = [254, 255, 256, 510, 511, 1_000, 3]
      packets = for size <- sizes, do: <<0xFC, :rand.bytes(size - 1)::binary>>
      data = WebMWriter.file(@head, [{:xiph, packets}, {:ebml, Enum.reverse(packets)}])
      assert WebM.packets([data]) |> Enum.to_list() == packets ++ Enum.reverse(packets)
    end

    test "BlockGroups, unknown sizes and other tracks", %{packets: packets} do
      blocks = packets |> Enum.map(&{:none, [&1]}) |> Enum.intersperse({:other_track, "subtitle"})

      for opts <- [
            [block_groups: true],
            [unknown_sizes: true],
            [block_groups: true, unknown_sizes: true]
          ] do
        data = WebMWriter.file(@head, blocks, opts)

        for size <- [64, 1] do
          assert WebM.packets(chunks(data, size)) |> Enum.to_list() == packets
        end
      end
    end

    test "a file without Opus audio is refused" do
      assert_raise ArgumentError, ~r/no Opus track.*A_VORBIS/, fn ->
        WebM.stream!(Path.join(@dir, "vorbis.webm")) |> Enum.to_list()
      end
    end

    test "an unused surround track does not prevent playback of the first stereo track", %{
      packets: packets
    } do
      surround = <<"OpusHead", 1, 6, 0::64, 1, 4, 2, 0, 4, 1, 2, 3, 5>>
      blocks = Enum.map(packets, &{:none, [&1]})
      tracks = [{1, 2, "A_OPUS", @head}, {2, 2, "A_OPUS", surround}]
      data = WebMWriter.file(@head, blocks, tracks: tracks)

      for size <- [65_536, 1] do
        assert WebM.packets(chunks(data, size)) |> Enum.to_list() == packets
      end

      selected_surround = [{1, 2, "A_OPUS", surround}, {2, 2, "A_OPUS", @head}]
      data = WebMWriter.file(surround, blocks, tracks: selected_surround)

      assert_raise ArgumentError, ~r/6-channel Opus/, fn ->
        WebM.packets(chunks(data, 1)) |> Enum.to_list()
      end
    end

    test "a live stream restarting mid-way starts over cleanly", %{packets: packets} do
      file = WebMWriter.file(@head, Enum.map(packets, &{:none, [&1]}), unknown_sizes: true)
      assert WebM.packets([file, file]) |> Enum.to_list() == packets ++ packets
    end

    test "a truncated file yields the packets before the cut" do
      data = File.read!(Path.join(@dir, "stereo.webm"))
      heard = WebM.packets([binary_part(data, 0, div(byte_size(data), 2))]) |> Enum.to_list()
      expected = WebM.stream!(Path.join(@dir, "stereo.webm")) |> Enum.to_list()
      assert heard != [] and heard == Enum.take(expected, length(heard))
    end
  end

  test "OpusHead checks" do
    assert Opus.check_head(@head) == :ok
    assert Opus.check_head(<<"OpusHead", 1, 1, 0::64, 0>>) == :ok
    # mapping family 1 with a single stream is still one ordinary Opus stream
    assert Opus.check_head(<<"OpusHead", 1, 2, 0::64, 1, 1, 1, 0, 1>>) == :ok
    assert {:error, _} = Opus.check_head(<<"OpusHead", 1, 6, 0::64, 1, 4, 2, 0, 4, 1, 2, 3, 5>>)
    assert {:error, _} = Opus.check_head(<<"OpusHead", 1, 3, 0::64, 0>>)
    assert {:error, _} = Opus.check_head(<<"OpusHead", 16, 2, 0::64, 0>>)
    assert {:error, _} = Opus.check_head("OpusHead")
  end

  # corrupt input must end in packets or a clear ArgumentError, never a crash
  # of any other kind and never unbounded buffering
  describe "corrupted input" do
    for {file, reader} <- [{"stereo_20ms.opus", Ogg}, {"stereo.webm", WebM}, {"live.webm", WebM}] do
      test "#{file} with random damage" do
        data = File.read!(Path.join(@dir, unquote(file)))
        :rand.seed(:exsss, {1, 2, 3})

        for _round <- 1..300 do
          damaged = damage(data)

          try do
            unquote(reader).packets(chunks(damaged, 500)) |> Enum.to_list()
          rescue
            ArgumentError -> :refused
          end
        end
      end
    end
  end

  defp damage(data) do
    case :rand.uniform(3) do
      # flip a few bytes
      1 ->
        Enum.reduce(1..:rand.uniform(8), data, fn _, data ->
          position = :rand.uniform(byte_size(data)) - 1
          <<before::binary-size(^position), _byte, rest::binary>> = data
          <<before::binary, :rand.uniform(256) - 1, rest::binary>>
        end)

      # cut a piece out
      2 ->
        position = :rand.uniform(byte_size(data)) - 1
        length = min(:rand.uniform(200), byte_size(data) - position)

        binary_part(data, 0, position) <>
          binary_part(data, position + length, byte_size(data) - position - length)

      # random bytes in front
      3 ->
        :rand.bytes(:rand.uniform(100)) <> data
    end
  end
end
