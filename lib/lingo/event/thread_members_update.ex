defmodule Lingo.Event.ThreadMembersUpdate do
  @moduledoc """
  The payload of `:thread_members_update`: users were added to or removed
  from a thread. `id` is the thread's; `member_count` stops at 50.
  """

  alias Lingo.Type.{Parse, ThreadMember}

  @type t :: %__MODULE__{
          id: String.t(),
          guild_id: String.t(),
          member_count: non_neg_integer(),
          added_members: [ThreadMember.t()],
          removed_member_ids: [String.t()]
        }

  defstruct [:id, :guild_id, member_count: 0, added_members: [], removed_member_ids: []]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    guild_id = data["guild_id"]

    %__MODULE__{
      id: data["id"],
      guild_id: guild_id,
      member_count: data["member_count"] || 0,
      added_members:
        Parse.list(data["added_members"], &ThreadMember.new(Parse.put_guild_id(&1, guild_id))),
      removed_member_ids: data["removed_member_ids"] || []
    }
  end
end
