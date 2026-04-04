defmodule Lingo.Type.Invite do
  @moduledoc false

  alias Lingo.Type.{Channel, Guild, User}

  @type t :: %__MODULE__{
          type: integer() | nil,
          code: String.t(),
          guild: Guild.t() | nil,
          channel: Channel.t() | nil,
          inviter: User.t() | nil,
          target_type: integer() | nil,
          target_user: User.t() | nil,
          approximate_presence_count: integer() | nil,
          approximate_member_count: integer() | nil,
          expires_at: String.t() | nil,
          uses: integer() | nil,
          max_uses: integer() | nil,
          max_age: integer() | nil,
          temporary: boolean(),
          created_at: String.t() | nil,
          flags: integer()
        }

  defstruct [
    :type,
    :code,
    :guild,
    :channel,
    :inviter,
    :target_type,
    :target_user,
    :approximate_presence_count,
    :approximate_member_count,
    :expires_at,
    :uses,
    :max_uses,
    :max_age,
    :created_at,
    temporary: false,
    flags: 0
  ]

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      type: data["type"],
      code: data["code"],
      guild: Guild.new(data["guild"]),
      channel: Channel.new(data["channel"]),
      inviter: User.new(data["inviter"]),
      target_type: data["target_type"],
      target_user: User.new(data["target_user"]),
      approximate_presence_count: data["approximate_presence_count"],
      approximate_member_count: data["approximate_member_count"],
      expires_at: data["expires_at"],
      uses: data["uses"],
      max_uses: data["max_uses"],
      max_age: data["max_age"],
      temporary: data["temporary"] || false,
      created_at: data["created_at"],
      flags: data["flags"] || 0
    }
  end
end
