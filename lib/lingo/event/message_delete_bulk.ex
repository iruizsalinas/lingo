defmodule Lingo.Event.MessageDeleteBulk do
  @moduledoc """
  The payload of `:message_delete_bulk`: several messages deleted at once.
  `old` holds those of them that were cached.
  """

  alias Lingo.Type.Message

  @type t :: %__MODULE__{
          ids: [String.t()],
          channel_id: String.t(),
          guild_id: String.t() | nil,
          old: [Message.t()]
        }

  defstruct [:channel_id, :guild_id, ids: [], old: []]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data),
    do: %__MODULE__{
      ids: data["ids"] || [],
      channel_id: data["channel_id"],
      guild_id: data["guild_id"]
    }
end
