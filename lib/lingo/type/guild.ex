defmodule Lingo.Type.Guild do
  @moduledoc "A guild (server)."

  alias Lingo.Type.{Channel, Codes, Emoji, Member, Parse, Role, Sticker}

  @type verification_level :: :none | :low | :medium | :high | :very_high
  @type notification_level :: :all_messages | :only_mentions
  @type explicit_filter :: :disabled | :members_without_roles | :all_members
  @type mfa_level :: :none | :elevated
  @type nsfw_level :: :default | :explicit | :safe | :age_restricted
  @type premium_tier :: :none | :tier_1 | :tier_2 | :tier_3

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          icon: String.t() | nil,
          splash: String.t() | nil,
          discovery_splash: String.t() | nil,
          owner: boolean(),
          owner_id: String.t(),
          permissions: String.t() | nil,
          afk_channel_id: String.t() | nil,
          afk_timeout: integer(),
          widget_enabled: boolean(),
          widget_channel_id: String.t() | nil,
          verification_level: verification_level(),
          default_message_notifications: notification_level(),
          explicit_content_filter: explicit_filter(),
          roles: [Role.t()],
          emojis: [Emoji.t()],
          features: [String.t()],
          mfa_level: mfa_level(),
          application_id: String.t() | nil,
          system_channel_id: String.t() | nil,
          system_channel_flags: integer(),
          rules_channel_id: String.t() | nil,
          max_presences: integer() | nil,
          max_members: integer() | nil,
          vanity_url_code: String.t() | nil,
          description: String.t() | nil,
          banner: String.t() | nil,
          premium_tier: premium_tier(),
          premium_subscription_count: integer(),
          preferred_locale: String.t(),
          public_updates_channel_id: String.t() | nil,
          max_video_channel_users: integer() | nil,
          max_stage_video_channel_users: integer() | nil,
          approximate_member_count: integer() | nil,
          approximate_presence_count: integer() | nil,
          welcome_screen: map() | nil,
          nsfw_level: nsfw_level(),
          stickers: [Sticker.t()],
          premium_progress_bar_enabled: boolean(),
          safety_alerts_channel_id: String.t() | nil,
          incidents_data: map() | nil,
          channels: [Channel.t()],
          members: [Lingo.Type.Member.t()],
          member_count: integer() | nil,
          joined_at: DateTime.t() | nil,
          large: boolean(),
          unavailable: boolean()
        }

  defstruct [
    :id,
    :name,
    :icon,
    :splash,
    :discovery_splash,
    :owner_id,
    :permissions,
    :afk_channel_id,
    :application_id,
    :system_channel_id,
    :rules_channel_id,
    :max_presences,
    :max_members,
    :vanity_url_code,
    :description,
    :banner,
    :public_updates_channel_id,
    :max_video_channel_users,
    :max_stage_video_channel_users,
    :approximate_member_count,
    :approximate_presence_count,
    :welcome_screen,
    :safety_alerts_channel_id,
    :incidents_data,
    :widget_channel_id,
    :member_count,
    :joined_at,
    preferred_locale: "en-US",
    owner: false,
    afk_timeout: 0,
    widget_enabled: false,
    verification_level: :none,
    default_message_notifications: :all_messages,
    explicit_content_filter: :disabled,
    roles: [],
    emojis: [],
    features: [],
    mfa_level: :none,
    system_channel_flags: 0,
    premium_tier: :none,
    premium_subscription_count: 0,
    nsfw_level: :default,
    stickers: [],
    premium_progress_bar_enabled: false,
    channels: [],
    members: [],
    large: false,
    unavailable: false
  ]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    guild = Parse.fields(__MODULE__, data)
    put_guild = &Parse.put_guild_id(&1, data["id"])

    struct(guild,
      verification_level: code(data, :verification_level, guild),
      default_message_notifications: code(data, :default_message_notifications, guild),
      explicit_content_filter: code(data, :explicit_content_filter, guild),
      mfa_level: code(data, :mfa_level, guild),
      nsfw_level: code(data, :nsfw_level, guild),
      premium_tier: code(data, :premium_tier, guild),
      roles: Parse.list(data["roles"], &(&1 |> put_guild.() |> Role.new())),
      members: Parse.list(data["members"], &(&1 |> put_guild.() |> Member.new())),
      emojis: Parse.list(data["emojis"], &Emoji.new/1),
      stickers: Parse.list(data["stickers"], &Sticker.new/1),
      channels: Parse.list(data["channels"], &Channel.new/1),
      joined_at: Parse.timestamp(data["joined_at"])
    )
  end

  # the struct already holds the default when Discord sent nothing
  defp code(data, field, guild),
    do: Codes.name(field, data[Atom.to_string(field)], Map.fetch!(guild, field))
end
