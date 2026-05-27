defmodule Lingo.Type.Member do
  @moduledoc false

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
          joined_at: String.t() | nil,
          premium_since: String.t() | nil,
          deaf: boolean(),
          mute: boolean(),
          flags: integer(),
          pending: boolean(),
          permissions: String.t() | nil,
          communication_disabled_until: String.t() | nil
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
      joined_at: data["joined_at"],
      premium_since: data["premium_since"],
      deaf: data["deaf"] || false,
      mute: data["mute"] || false,
      flags: data["flags"] || 0,
      pending: data["pending"] || false,
      permissions: data["permissions"],
      communication_disabled_until: data["communication_disabled_until"]
    }
  end
end
