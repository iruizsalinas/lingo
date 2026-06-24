defmodule Lingo.Type.Invite do
  @moduledoc false

  alias Lingo.Type.{Channel, Guild, Role, ScheduledEvent, User}

  @type t :: %__MODULE__{
          type: integer() | nil,
          code: String.t(),
          guild_id: String.t() | nil,
          channel_id: String.t() | nil,
          guild: Guild.t() | nil,
          channel: Channel.t() | nil,
          inviter: User.t() | nil,
          target_type: integer() | nil,
          target_user: User.t() | nil,
          target_application: map() | nil,
          approximate_presence_count: integer() | nil,
          approximate_member_count: integer() | nil,
          expires_at: String.t() | nil,
          guild_scheduled_event: ScheduledEvent.t() | nil,
          roles: [Role.t()],
          uses: integer() | nil,
          max_uses: integer() | nil,
          max_age: integer() | nil,
          temporary: boolean(),
          created_at: String.t() | nil,
          role_ids: [String.t()],
          flags: integer()
        }

  defstruct [
    :type,
    :code,
    :guild_id,
    :channel_id,
    :guild,
    :channel,
    :inviter,
    :target_type,
    :target_user,
    :target_application,
    :approximate_presence_count,
    :approximate_member_count,
    :expires_at,
    :guild_scheduled_event,
    :uses,
    :max_uses,
    :max_age,
    :created_at,
    role_ids: [],
    roles: [],
    temporary: false,
    flags: 0
  ]

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      type: data["type"],
      code: data["code"],
      guild_id: data["guild_id"],
      channel_id: data["channel_id"],
      guild: Guild.new(data["guild"]),
      channel: Channel.new(data["channel"]),
      inviter: User.new(data["inviter"]),
      target_type: data["target_type"],
      target_user: User.new(data["target_user"]),
      target_application: data["target_application"],
      approximate_presence_count: data["approximate_presence_count"],
      approximate_member_count: data["approximate_member_count"],
      expires_at: data["expires_at"],
      guild_scheduled_event: ScheduledEvent.new(data["guild_scheduled_event"]),
      roles:
        (data["roles"] || [])
        |> Enum.map(fn role -> Role.new(maybe_put_guild_id(role, data["guild_id"])) end),
      uses: data["uses"],
      max_uses: data["max_uses"],
      max_age: data["max_age"],
      temporary: data["temporary"] || false,
      created_at: data["created_at"],
      role_ids: data["role_ids"] || [],
      flags: data["flags"] || 0
    }
  end

  defp maybe_put_guild_id(data, nil), do: data

  defp maybe_put_guild_id(data, guild_id) when is_map(data),
    do: Map.put(data, "guild_id", guild_id)
end
