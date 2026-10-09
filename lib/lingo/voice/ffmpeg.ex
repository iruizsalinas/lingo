defmodule Lingo.Voice.FFmpeg do
  @moduledoc """
  Plays anything ffmpeg can read: it transcodes the input to Ogg Opus in an
  external `ffmpeg` process and streams the Opus packets out of its output.

  ffmpeg must be on the PATH; no native code is linked into the VM.
  """

  alias Lingo.Voice.Ogg

  @doc """
  Streams the Opus packets of `input`, a file path or URL.

  Options:

    * `:bitrate` - Opus bitrate in bits per second, defaults to 64000
    * `:ffmpeg` - path to the ffmpeg executable
  """
  @spec stream(String.t(), keyword()) :: Enumerable.t()
  def stream(input, opts \\ []) do
    Stream.resource(fn -> open(input, opts) end, &read/1, &close/1) |> Ogg.packets()
  end

  @doc false
  def args(input, opts) do
    ~w(-hide_banner -loglevel error -i) ++
      [input] ++
      ~w(-vn -c:a libopus -ar 48000 -ac 2 -frame_duration 20 -application audio) ++
      ["-b:a", to_string(Keyword.get(opts, :bitrate, 64_000))] ++ ~w(-f ogg pipe:1)
  end

  defp open(input, opts) do
    executable = Keyword.get_lazy(opts, :ffmpeg, fn -> System.find_executable("ffmpeg") end)
    if executable == nil, do: raise("ffmpeg was not found on the PATH")

    Port.open({:spawn_executable, executable}, [:binary, :exit_status, args: args(input, opts)])
  end

  defp read(port) do
    receive do
      {^port, {:data, data}} -> {[data], port}
      {^port, {:exit_status, _status}} -> {:halt, port}
    end
  end

  defp close(port) do
    if Port.info(port), do: Port.close(port)
  end
end
