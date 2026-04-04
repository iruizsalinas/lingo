defmodule Lingo.Type.Guild do
  @moduledoc false

  alias Lingo.Type.{Channel, Emoji, Role, Sticker}

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
          nsfw_level: nsfw_level(),
          stickers: [Sticker.t()],
          premium_progress_bar_enabled: boolean(),
          safety_alerts_channel_id: String.t() | nil,
          incidents_data: map() | nil,
          channels: [Channel.t()],
          members: [Lingo.Type.Member.t()],
          member_count: integer() | nil,
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
    :preferred_locale,
    :public_updates_channel_id,
    :max_video_channel_users,
    :max_stage_video_channel_users,
    :approximate_member_count,
    :approximate_presence_count,
    :safety_alerts_channel_id,
    :incidents_data,
    :widget_channel_id,
    :member_count,
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

  @verification_levels %{0 => :none, 1 => :low, 2 => :medium, 3 => :high, 4 => :very_high}
  @notification_levels %{0 => :all_messages, 1 => :only_mentions}
  @explicit_filters %{0 => :disabled, 1 => :members_without_roles, 2 => :all_members}
  @mfa_levels %{0 => :none, 1 => :elevated}
  @nsfw_levels %{0 => :default, 1 => :explicit, 2 => :safe, 3 => :age_restricted}
  @premium_tiers %{0 => :none, 1 => :tier_1, 2 => :tier_2, 3 => :tier_3}

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      name: data["name"],
      icon: data["icon"],
      splash: data["splash"],
      discovery_splash: data["discovery_splash"],
      owner: data["owner"] || false,
      owner_id: data["owner_id"],
      permissions: data["permissions"],
      afk_channel_id: data["afk_channel_id"],
      afk_timeout: data["afk_timeout"] || 0,
      widget_enabled: data["widget_enabled"] || false,
      widget_channel_id: data["widget_channel_id"],
      verification_level: Map.get(@verification_levels, data["verification_level"], :none),
      default_message_notifications:
        Map.get(@notification_levels, data["default_message_notifications"], :all_messages),
      explicit_content_filter:
        Map.get(@explicit_filters, data["explicit_content_filter"], :disabled),
      roles: (data["roles"] || []) |> Enum.map(&Role.new/1),
      emojis: (data["emojis"] || []) |> Enum.map(&Emoji.new/1),
      features: data["features"] || [],
      mfa_level: Map.get(@mfa_levels, data["mfa_level"], :none),
      application_id: data["application_id"],
      system_channel_id: data["system_channel_id"],
      system_channel_flags: data["system_channel_flags"] || 0,
      rules_channel_id: data["rules_channel_id"],
      max_presences: data["max_presences"],
      max_members: data["max_members"],
      vanity_url_code: data["vanity_url_code"],
      description: data["description"],
      banner: data["banner"],
      premium_tier: Map.get(@premium_tiers, data["premium_tier"], :none),
      premium_subscription_count: data["premium_subscription_count"] || 0,
      preferred_locale: data["preferred_locale"] || "en-US",
      public_updates_channel_id: data["public_updates_channel_id"],
      max_video_channel_users: data["max_video_channel_users"],
      max_stage_video_channel_users: data["max_stage_video_channel_users"],
      approximate_member_count: data["approximate_member_count"],
      approximate_presence_count: data["approximate_presence_count"],
      nsfw_level: Map.get(@nsfw_levels, data["nsfw_level"], :default),
      stickers: (data["stickers"] || []) |> Enum.map(&Sticker.new/1),
      premium_progress_bar_enabled: data["premium_progress_bar_enabled"] || false,
      safety_alerts_channel_id: data["safety_alerts_channel_id"],
      incidents_data: data["incidents_data"],
      channels: (data["channels"] || []) |> Enum.map(&Channel.new/1),
      members: (data["members"] || []) |> Enum.map(&Lingo.Type.Member.new/1),
      member_count: data["member_count"],
      large: data["large"] || false,
      unavailable: data["unavailable"] || false
    }
  end
end
