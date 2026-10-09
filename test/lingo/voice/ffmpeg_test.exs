defmodule Lingo.Voice.FFmpegTest do
  use ExUnit.Case, async: true

  # Runs the real ffmpeg on the inputs bots usually play. Skipped when
  # ffmpeg isn't on the PATH.

  alias Lingo.Voice.{FFmpeg, Ogg, Opus}

  @moduletag :ffmpeg
  @moduletag :tmp_dir

  defp ffmpeg!(args) do
    {output, 0} =
      System.cmd(System.find_executable("ffmpeg"), ~w(-hide_banner -loglevel error -y) ++ args,
        stderr_to_stdout: true
      )

    output
  end

  # two seconds of `source` (a lavfi graph) encoded with `codec_args` into `name`
  defp input(dir, name, source, codec_args) do
    path = Path.join(dir, name)
    ffmpeg!(["-f", "lavfi", "-i", source, "-t", "2"] ++ codec_args ++ [path])
    path
  end

  @tone "sine=frequency=440:sample_rate=44100"

  test "transcodes every common input to 20 ms stereo Opus", %{tmp_dir: dir} do
    inputs = [
      input(dir, "cbr.mp3", @tone, ~w(-ac 2 -c:a libmp3lame -b:a 128k)),
      input(
        dir,
        "vbr_mono.mp3",
        "sine=frequency=440:sample_rate=22050",
        ~w(-c:a libmp3lame -q:a 4)
      ),
      input(dir, "song.m4a", @tone, ~w(-c:a aac -b:a 128k)),
      input(dir, "song.flac", @tone, ~w(-c:a flac)),
      input(dir, "old.wav", "sine=frequency=440:sample_rate=8000", ~w(-c:a pcm_u8)),
      input(dir, "song.ogg", @tone, ~w(-c:a libvorbis)),
      input(dir, "song.webm", @tone, ~w(-c:a libopus)),
      input(
        dir,
        "surround.wav",
        "#{@tone},pan=5.1|FL=c0|FR=c0|FC=c0|LFE=c0|BL=c0|BR=c0",
        ~w(-c:a pcm_s16le)
      ),
      input(
        dir,
        "video.mkv",
        "testsrc=size=64x64:rate=10[out0];#{@tone}[out1]",
        ~w(-c:v mpeg4 -c:a aac)
      )
    ]

    for path <- inputs do
      packets = FFmpeg.stream(path) |> Enum.to_list()

      # 2 s of audio in 20 ms packets, give or take the encoder's padding
      assert length(packets) in 99..103, "#{Path.basename(path)}: #{length(packets)} packets"
      assert Enum.all?(packets, &(Opus.samples(&1) == 960)), Path.basename(path)
    end
  end

  test "what comes out of the pipe is what ffmpeg writes to a file", %{tmp_dir: dir} do
    path = input(dir, "song.flac", @tone, ~w(-c:a flac))
    file = Path.join(dir, "out.opus")
    ffmpeg!(Enum.drop(FFmpeg.args(path, []), 3) |> List.replace_at(-1, file))

    assert FFmpeg.stream(path) |> Enum.to_list() == Ogg.stream!(file) |> Enum.to_list()
  end

  test "reads URLs", %{tmp_dir: dir} do
    input(dir, "song.mp3", @tone, ~w(-c:a libmp3lame))
    :inets.start()

    {:ok, server} =
      :inets.start(:httpd,
        port: 0,
        server_name: ~c"lingo",
        server_root: String.to_charlist(dir),
        document_root: String.to_charlist(dir),
        bind_address: {127, 0, 0, 1}
      )

    on_exit(fn -> :inets.stop(:httpd, server) end)
    port = :httpd.info(server)[:port]

    packets = FFmpeg.stream("http://127.0.0.1:#{port}/song.mp3") |> Enum.to_list()
    assert length(packets) in 99..103
  end

  test "a missing input fails loudly instead of playing nothing" do
    assert_raise RuntimeError, ~r/ffmpeg failed/, fn ->
      FFmpeg.stream("does/not/exist.mp3") |> Enum.to_list()
    end
  end

  test "stopping playback ends ffmpeg too", %{tmp_dir: dir} do
    path = input(dir, "long.flac", "sine=frequency=440:duration=600", ~w(-t 600 -c:a flac))
    test = self()

    consumer =
      spawn(fn ->
        FFmpeg.stream(path) |> Stream.each(fn _ -> send(test, :packet) end) |> Stream.run()
      end)

    assert_receive :packet, 5_000

    [os_pid] =
      for port <- Port.list(), Port.info(port, :connected) == {:connected, consumer} do
        {:os_pid, os_pid} = Port.info(port, :os_pid)
        os_pid
      end

    assert os_process_alive?(os_pid)
    Process.exit(consumer, :kill)

    assert Enum.any?(1..50, fn _ ->
             Process.sleep(100)
             not os_process_alive?(os_pid)
           end),
           "ffmpeg (#{os_pid}) outlived its player"
  end

  defp os_process_alive?(os_pid) do
    case :os.type() do
      {:win32, _} ->
        {output, 0} = System.cmd("tasklist", ["/FI", "PID eq #{os_pid}", "/NH"])
        output =~ "#{os_pid}"

      {:unix, _} ->
        match?({_, 0}, System.cmd("kill", ["-0", "#{os_pid}"], stderr_to_stdout: true))
    end
  end
end
