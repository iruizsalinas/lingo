defmodule Lingo.Type.Channel do
  @moduledoc """
  A guild channel, thread, DM or group DM.

  `type` is an atom such as `:guild_text` or `:public_thread`, or Discord's
  number for types Lingo doesn't know yet.
  """

  import Bitwise

  alias Lingo.Type.{Codes, Message, Overwrite, Parse, ThreadMember, User}

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
          application_id: String.t() | nil,
          managed: boolean(),
          parent_id: String.t() | nil,
          last_pin_timestamp: DateTime.t() | nil,
          rtc_region: String.t() | nil,
          video_quality_mode: integer() | nil,
          message_count: integer() | nil,
          member_count: integer() | nil,
          thread_metadata: map() | nil,
          member: Lingo.Type.ThreadMember.t() | nil,
          default_auto_archive_duration: integer() | nil,
          permissions: String.t() | nil,
          app_permissions: String.t() | nil,
          flags: integer(),
          total_message_sent: integer() | nil,
          available_tags: [map()],
          applied_tags: [String.t()],
          default_reaction_emoji: map() | nil,
          default_thread_rate_limit_per_user: integer() | nil,
          default_sort_order: integer() | nil,
          default_forum_layout: integer() | nil,
          message: Message.t() | nil
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
    :application_id,
    :parent_id,
    :last_pin_timestamp,
    :rtc_region,
    :video_quality_mode,
    :message_count,
    :member_count,
    :thread_metadata,
    :member,
    :default_auto_archive_duration,
    :permissions,
    :app_permissions,
    :total_message_sent,
    :default_reaction_emoji,
    :default_thread_rate_limit_per_user,
    :default_sort_order,
    :default_forum_layout,
    :message,
    permission_overwrites: [],
    recipients: [],
    nsfw: false,
    managed: false,
    flags: 0,
    available_tags: [],
    applied_tags: []
  ]

  @channel_obfuscated 1 <<< 17

  @doc "Returns whether Discord has hidden this channel's sensitive metadata."
  @spec obfuscated?(t()) :: boolean()
  def obfuscated?(%__MODULE__{flags: flags}) when is_integer(flags) do
    band(flags, @channel_obfuscated) == @channel_obfuscated
  end

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    struct(Parse.fields(__MODULE__, data),
      type: Codes.name(:channel_type, data["type"]),
      permission_overwrites: Parse.list(data["permission_overwrites"], &Overwrite.new/1),
      recipients: Parse.list(data["recipients"], &User.new/1),
      last_pin_timestamp: Parse.timestamp(data["last_pin_timestamp"]),
      message: Message.new(data["message"]),
      member: ThreadMember.new(data["member"])
    )
  end
end
