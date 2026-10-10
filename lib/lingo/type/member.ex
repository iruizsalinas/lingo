defmodule Lingo.Type.Member do
  @moduledoc "A guild member: the user plus their nickname, roles and guild-specific state."

  alias Lingo.Type.User

  @type t :: %__MODULE__{
          guild_id: String.t() | nil,
          user: User.t() | nil,
          nick: String.t() | nil,
          avatar: String.t() | nil,
          banner: String.t() | nil,
          avatar_decoration_data: map() | nil,
          collectibles: map() | nil,
          roles: [String.t()],
          joined_at: DateTime.t() | nil,
          premium_since: DateTime.t() | nil,
          deaf: boolean(),
          mute: boolean(),
          flags: integer(),
          pending: boolean(),
          permissions: String.t() | nil,
          communication_disabled_until: DateTime.t() | nil
        }

  defstruct [
    :guild_id,
    :user,
    :nick,
    :avatar,
    :banner,
    :avatar_decoration_data,
    :collectibles,
    :joined_at,
    :premium_since,
    :permissions,
    :communication_disabled_until,
    roles: [],
    deaf: false,
    mute: false,
    flags: 0,
    pending: false
  ]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      guild_id: data["guild_id"],
      user: User.new(data["user"]),
      nick: data["nick"],
      avatar: data["avatar"],
      banner: data["banner"],
      avatar_decoration_data: data["avatar_decoration_data"],
      collectibles: data["collectibles"],
      roles: data["roles"] || [],
      joined_at: Lingo.Type.Parse.timestamp(data["joined_at"]),
      premium_since: Lingo.Type.Parse.timestamp(data["premium_since"]),
      deaf: data["deaf"] || false,
      mute: data["mute"] || false,
      flags: data["flags"] || 0,
      pending: data["pending"] || false,
      permissions: data["permissions"],
      communication_disabled_until:
        Lingo.Type.Parse.timestamp(data["communication_disabled_until"])
    }
  end
end
