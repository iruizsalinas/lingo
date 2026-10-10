defmodule Lingo.Event.GuildStickersUpdate do
  @moduledoc """
  The payload of `:guild_stickers_update`: a guild's full sticker list after
  a change. `old` is the list as cached, or `nil` when the guild isn't cached.
  """

  alias Lingo.Type.Sticker

  @type t :: %__MODULE__{
          guild_id: String.t(),
          stickers: [Sticker.t()],
          old: [Sticker.t()] | nil
        }

  defstruct [:guild_id, :old, stickers: []]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      guild_id: data["guild_id"],
      stickers: Lingo.Type.Parse.list(data["stickers"], &Sticker.new/1)
    }
  end
end
