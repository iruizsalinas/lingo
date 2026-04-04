defmodule Lingo.Type.Channel do
  @moduledoc false

  @type channel_type ::
          :guild_text
          | :dm
          | :guild_voice
          | :group_dm
          | :guild_category
          | :guild_announcement
          | :announcement_thread
          | :public_thread
          | :private_thread
          | :guild_stage_voice
          | :guild_directory
          | :guild_forum
          | :guild_media

  @type t :: %__MODULE__{
          id: String.t(),
          type: channel_type(),
          guild_id: String.t() | nil,
          position: integer() | nil,
          permission_overwrites: [Lingo.Type.Overwrite.t()],
          name: String.t() | nil,
          topic: String.t() | nil,
          nsfw: boolean(),
          last_message_id: String.t() | nil,
          bitrate: integer() | nil,
          user_limit: integer() | nil,
          rate_limit_per_user: integer() | nil,
          recipients: [Lingo.Type.User.t()],
          icon: String.t() | nil,
          owner_id: String.t() | nil,
          parent_id: String.t() | nil,
          last_pin_timestamp: String.t() | nil,
          rtc_region: String.t() | nil,
          video_quality_mode: integer() | nil,
          message_count: integer() | nil,
          member_count: integer() | nil,
          thread_metadata: map() | nil,
          default_auto_archive_duration: integer() | nil,
          permissions: String.t() | nil,
          flags: integer(),
          total_message_sent: integer() | nil,
          available_tags: [map()],
          applied_tags: [String.t()],
          default_reaction_emoji: map() | nil,
          default_thread_rate_limit_per_user: integer() | nil,
          default_sort_order: integer() | nil,
          default_forum_layout: integer() | nil
        }

  defstruct [
    :id,
    :type,
    :guild_id,
    :position,
    :name,
    :topic,
    :last_message_id,
    :bitrate,
    :user_limit,
    :rate_limit_per_user,
    :icon,
    :owner_id,
    :parent_id,
    :last_pin_timestamp,
    :rtc_region,
    :video_quality_mode,
    :message_count,
    :member_count,
    :thread_metadata,
    :default_auto_archive_duration,
    :permissions,
    :total_message_sent,
    :default_reaction_emoji,
    :default_thread_rate_limit_per_user,
    :default_sort_order,
    :default_forum_layout,
    permission_overwrites: [],
    recipients: [],
    nsfw: false,
    flags: 0,
    available_tags: [],
    applied_tags: []
  ]

  @channel_types %{
    0 => :guild_text,
    1 => :dm,
    2 => :guild_voice,
    3 => :group_dm,
    4 => :guild_category,
    5 => :guild_announcement,
    10 => :announcement_thread,
    11 => :public_thread,
    12 => :private_thread,
    13 => :guild_stage_voice,
    14 => :guild_directory,
    15 => :guild_forum,
    16 => :guild_media
  }

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      type: Map.get(@channel_types, data["type"], data["type"]),
      guild_id: data["guild_id"],
      position: data["position"],
      permission_overwrites:
        (data["permission_overwrites"] || []) |> Enum.map(&Lingo.Type.Overwrite.new/1),
      name: data["name"],
      topic: data["topic"],
      nsfw: data["nsfw"] || false,
      last_message_id: data["last_message_id"],
      bitrate: data["bitrate"],
      user_limit: data["user_limit"],
      rate_limit_per_user: data["rate_limit_per_user"],
      recipients: (data["recipients"] || []) |> Enum.map(&Lingo.Type.User.new/1),
      icon: data["icon"],
      owner_id: data["owner_id"],
      parent_id: data["parent_id"],
      last_pin_timestamp: data["last_pin_timestamp"],
      rtc_region: data["rtc_region"],
      video_quality_mode: data["video_quality_mode"],
      message_count: data["message_count"],
      member_count: data["member_count"],
      thread_metadata: data["thread_metadata"],
      default_auto_archive_duration: data["default_auto_archive_duration"],
      permissions: data["permissions"],
      flags: data["flags"] || 0,
      total_message_sent: data["total_message_sent"],
      available_tags: data["available_tags"] || [],
      applied_tags: data["applied_tags"] || [],
      default_reaction_emoji: data["default_reaction_emoji"],
      default_thread_rate_limit_per_user: data["default_thread_rate_limit_per_user"],
      default_sort_order: data["default_sort_order"],
      default_forum_layout: data["default_forum_layout"]
    }
  end
end

defmodule Lingo.Type.Overwrite do
  @moduledoc false

  @type overwrite_type :: :role | :member

  @type t :: %__MODULE__{
          id: String.t(),
          type: overwrite_type(),
          allow: String.t(),
          deny: String.t()
        }

  defstruct [:id, :type, :allow, :deny]

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      type: if(data["type"] == 0, do: :role, else: :member),
      allow: data["allow"] || "0",
      deny: data["deny"] || "0"
    }
  end
end
