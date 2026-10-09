defmodule Lingo.Voice do
  @moduledoc """
  Voice: joining channels, playing audio and receiving it.

  Audio is Opus all the way through. Lingo has no native dependencies, so it
  can't encode or decode raw PCM itself; play Ogg Opus files with
  `play_file/2`, anything ffmpeg understands with `play_url/3`, or any
  enumerable of Opus packets with `play/2`. Received audio arrives as Opus
  packets per user.

  End-to-end encryption (DAVE) is handled transparently: Discord requires it,
  and media is never sent unencrypted while it is on.

      {:ok, _connection} = Lingo.Voice.join(guild_id, channel_id)
      Lingo.Voice.play_file(guild_id, "hello.opus")

      Lingo.Voice.listen(guild_id)

      receive do
        {:lingo_voice, ^guild_id, {:audio, user_id, %{opus: opus}}} -> ...
      end
  """

  alias Lingo.Voice.{Connection, FFmpeg, Manager, Ogg}

  @doc """
  Joins a voice channel and waits until audio can flow.

  Options: `:self_mute`, `:self_deaf` and `:timeout` (ms, default 20000).
  """
  @spec join(String.t() | integer(), String.t() | integer(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def join(guild_id, channel_id, opts \\ []), do: Manager.join(guild_id, channel_id, opts)

  @spec leave(String.t() | integer()) :: :ok
  def leave(guild_id), do: Manager.leave(guild_id)

  @doc "Plays an enumerable of Opus packets, replacing whatever is playing."
  @spec play(String.t() | integer(), Enumerable.t()) :: :ok | {:error, :not_connected}
  def play(guild_id, packets), do: with_connection(guild_id, &Connection.play(&1, packets))

  @doc "Plays an Ogg Opus file."
  @spec play_file(String.t() | integer(), Path.t()) :: :ok | {:error, :not_connected}
  def play_file(guild_id, path), do: play(guild_id, Ogg.stream!(path))

  @doc "Plays anything ffmpeg can read, transcoding it on the fly. Needs ffmpeg installed."
  @spec play_url(String.t() | integer(), String.t(), keyword()) :: :ok | {:error, :not_connected}
  def play_url(guild_id, input, opts \\ []), do: play(guild_id, FFmpeg.stream(input, opts))

  @spec stop(String.t() | integer()) :: :ok | {:error, :not_connected}
  def stop(guild_id), do: with_connection(guild_id, &Connection.stop_playback/1)

  @doc """
  Sends voice events for the guild to the calling process, including every
  Opus packet received. See `Lingo.Voice.Connection` for the messages.
  """
  @spec listen(String.t() | integer()) :: :ok | {:error, :not_connected}
  def listen(guild_id), do: with_connection(guild_id, &Connection.subscribe(&1, self()))

  @spec connection(String.t() | integer()) :: pid() | nil
  def connection(guild_id), do: Manager.connection(guild_id)

  defp with_connection(guild_id, fun) do
    case connection(guild_id) do
      nil -> {:error, :not_connected}
      pid -> fun.(pid)
    end
  end
end
