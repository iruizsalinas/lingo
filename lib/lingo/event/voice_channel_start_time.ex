defmodule Lingo.Event.VoiceChannelStartTime do
  @moduledoc """
  The payload of `:voice_channel_start_time_update`: when a voice channel's
  current call started, or `nil` once it's empty. `id` is the channel's.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          guild_id: String.t(),
          voice_start_time: DateTime.t() | nil
        }

  defstruct [:id, :guild_id, :voice_start_time]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      guild_id: data["guild_id"],
      voice_start_time: Lingo.Type.Parse.unix(data["voice_start_time"])
    }
  end
end
