defmodule Lingo.Type.SoundboardSound do
  @moduledoc """
  A soundboard sound. Discord's default sounds have no `guild_id`; a sound
  that isn't `available` belongs to a guild that lost the boosts it needs.
  """

  alias Lingo.Type.User

  @type t :: %__MODULE__{
          sound_id: String.t(),
          name: String.t(),
          volume: float(),
          emoji_id: String.t() | nil,
          emoji_name: String.t() | nil,
          guild_id: String.t() | nil,
          available: boolean(),
          user: User.t() | nil
        }

  defstruct [
    :sound_id,
    :name,
    :emoji_id,
    :emoji_name,
    :guild_id,
    :user,
    volume: 1.0,
    available: true
  ]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      sound_id: data["sound_id"],
      name: data["name"],
      volume: data["volume"] || 1.0,
      emoji_id: data["emoji_id"],
      emoji_name: data["emoji_name"],
      guild_id: data["guild_id"],
      available: Map.get(data, "available", true),
      user: User.new(data["user"])
    }
  end
end
