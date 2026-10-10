defmodule Lingo.Event.ThreadListSync do
  @moduledoc """
  The payload of `:thread_list_sync`: the active threads of a guild, or of
  some of its channels (`channel_ids`, `nil` for the whole guild), sent when
  the bot gains access to them. `members` are the bot's own memberships.
  """

  alias Lingo.Type.{Channel, Parse, ThreadMember}

  @type t :: %__MODULE__{
          guild_id: String.t(),
          channel_ids: [String.t()] | nil,
          threads: [Channel.t()],
          members: [ThreadMember.t()]
        }

  defstruct [:guild_id, :channel_ids, threads: [], members: []]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    guild_id = data["guild_id"]

    %__MODULE__{
      guild_id: guild_id,
      channel_ids: data["channel_ids"],
      threads: Parse.list(data["threads"], &Channel.new(Parse.put_guild_id(&1, guild_id))),
      members: Parse.list(data["members"], &ThreadMember.new(Parse.put_guild_id(&1, guild_id)))
    }
  end
end
