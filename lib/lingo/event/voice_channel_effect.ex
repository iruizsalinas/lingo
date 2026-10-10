defmodule Lingo.Event.VoiceChannelEffect do
  @moduledoc """
  The payload of `:voice_channel_effect_send`: someone sent an emoji
  reaction or a soundboard sound in a voice channel the bot is in.
  `animation_type` is `:premium` or `:basic`; `sound_id` is a snowflake for
  guild sounds and an integer for Discord's default ones.
  """

  alias Lingo.Type.Emoji

  @type t :: %__MODULE__{
          channel_id: String.t(),
          guild_id: String.t(),
          user_id: String.t(),
          emoji: Emoji.t() | nil,
          animation_type: :premium | :basic | integer() | nil,
          animation_id: integer() | nil,
          sound_id: String.t() | integer() | nil,
          sound_volume: float() | nil
        }

  defstruct [
    :channel_id,
    :guild_id,
    :user_id,
    :emoji,
    :animation_type,
    :animation_id,
    :sound_id,
    :sound_volume
  ]

  @animation_types %{0 => :premium, 1 => :basic}

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    struct(Lingo.Type.Parse.fields(__MODULE__, data),
      emoji: Emoji.new(data["emoji"]),
      animation_type: Map.get(@animation_types, data["animation_type"], data["animation_type"])
    )
  end
end
