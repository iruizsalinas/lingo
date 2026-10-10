defmodule Lingo.Type.ThreadMember do
  @moduledoc """
  A user's membership in a thread.

  `id` (the thread) and `user_id` are missing on the members inside a
  channel. `member` comes with `:thread_members_update` events and when asked
  for with `with_member`; `presence` only with `:thread_members_update`.
  """

  alias Lingo.Type.{Member, Parse, Presence}

  @type t :: %__MODULE__{
          id: String.t() | nil,
          user_id: String.t() | nil,
          guild_id: String.t() | nil,
          join_timestamp: DateTime.t() | nil,
          flags: integer(),
          member: Member.t() | nil,
          presence: Presence.t() | nil
        }

  defstruct [:id, :user_id, :guild_id, :join_timestamp, :member, :presence, flags: 0]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    guild_id = data["guild_id"]

    %__MODULE__{
      id: data["id"],
      user_id: data["user_id"],
      guild_id: guild_id,
      join_timestamp: Parse.timestamp(data["join_timestamp"]),
      flags: data["flags"] || 0,
      member: nested(Member, data["member"], guild_id),
      presence: nested(Presence, data["presence"], guild_id)
    }
  end

  defp nested(_type, nil, _guild_id), do: nil
  defp nested(type, data, guild_id), do: type.new(Parse.put_guild_id(data, guild_id))
end
