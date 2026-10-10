defmodule Lingo.Event.GuildEmojisUpdate do
  @moduledoc """
  The payload of `:guild_emojis_update`: a guild's full emoji list after a
  change. `old` is the list as cached, or `nil` when the guild isn't cached.
  """

  alias Lingo.Type.Emoji

  @type t :: %__MODULE__{guild_id: String.t(), emojis: [Emoji.t()], old: [Emoji.t()] | nil}

  defstruct [:guild_id, :old, emojis: []]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      guild_id: data["guild_id"],
      emojis: Lingo.Type.Parse.list(data["emojis"], &Emoji.new/1)
    }
  end
end
