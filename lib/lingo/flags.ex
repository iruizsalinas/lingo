defmodule Lingo.Flags do
  @moduledoc """
  Flag bitfields other than permissions (see `Lingo.Permissions`).

  Structs keep Discord's integer in their `flags` field (`public_flags` for
  users); these functions read and build it with atoms, Discord's names
  lowercased. `kind` is one of `:message`, `:user`, `:member`, `:channel`,
  `:attachment`, `:system_channel`, `:role`, `:application`, `:embed` or `:sku`.

      Lingo.Flags.has?(:message, message.flags, :is_voice_message)
      Lingo.Flags.to_list(:user, user.public_flags)
      #=> [:hypesquad_online_house_1, :verified_developer]
      Lingo.Flags.from_list(:message, [:suppress_embeds, :suppress_notifications])
      #=> 4100
  """

  import Bitwise

  @flags %{
    message: [
      crossposted: 0,
      is_crosspost: 1,
      suppress_embeds: 2,
      source_message_deleted: 3,
      urgent: 4,
      has_thread: 5,
      ephemeral: 6,
      loading: 7,
      failed_to_mention_some_roles_in_thread: 8,
      suppress_notifications: 12,
      is_voice_message: 13,
      has_snapshot: 14,
      is_components_v2: 15
    ],
    user: [
      staff: 0,
      partner: 1,
      hypesquad: 2,
      bug_hunter_level_1: 3,
      hypesquad_online_house_1: 6,
      hypesquad_online_house_2: 7,
      hypesquad_online_house_3: 8,
      premium_early_supporter: 9,
      team_pseudo_user: 10,
      bug_hunter_level_2: 14,
      verified_bot: 16,
      verified_developer: 17,
      certified_moderator: 18,
      bot_http_interactions: 19
    ],
    member: [
      did_rejoin: 0,
      completed_onboarding: 1,
      bypasses_verification: 2,
      started_onboarding: 3,
      is_guest: 4,
      started_home_actions: 5,
      completed_home_actions: 6,
      automod_quarantined_username: 7,
      dm_settings_upsell_acknowledged: 9,
      automod_quarantined_guild_tag: 10
    ],
    channel: [
      pinned: 1,
      require_tag: 4,
      hide_media_download_options: 15,
      channel_obfuscated: 17,
      is_spoiler_channel: 21
    ],
    attachment: [is_clip: 0, is_thumbnail: 1, is_remix: 2, is_spoiler: 3, is_animated: 5],
    system_channel: [
      suppress_join_notifications: 0,
      suppress_premium_subscriptions: 1,
      suppress_guild_reminder_notifications: 2,
      suppress_join_notification_replies: 3,
      suppress_role_subscription_purchase_notifications: 4,
      suppress_role_subscription_purchase_notification_replies: 5
    ],
    role: [in_prompt: 0],
    application: [
      application_auto_moderation_rule_create_badge: 6,
      gateway_presence: 12,
      gateway_presence_limited: 13,
      gateway_guild_members: 14,
      gateway_guild_members_limited: 15,
      verification_pending_guild_limit: 16,
      embedded: 17,
      gateway_message_content: 18,
      gateway_message_content_limited: 19,
      application_command_badge: 23
    ],
    embed: [is_content_inventory_entry: 5],
    sku: [available: 2, guild_subscription: 7, user_subscription: 8]
  }

  @type kind ::
          :message
          | :user
          | :member
          | :channel
          | :attachment
          | :system_channel
          | :role
          | :application
          | :embed
          | :sku

  @doc "Whether `flag` is set. Bitfields may be integers or strings (as in `flags_new`)."
  @spec has?(kind(), integer() | String.t() | nil, atom()) :: boolean()
  def has?(kind, bitfield, flag), do: band(int(bitfield), bit(kind, flag)) != 0

  @doc "The flags set in a bitfield. Bits Lingo doesn't know are left out."
  @spec to_list(kind(), integer() | String.t() | nil) :: [atom()]
  def to_list(kind, bitfield) do
    bitfield = int(bitfield)
    for {flag, shift} <- Map.fetch!(@flags, kind), band(bitfield, 1 <<< shift) != 0, do: flag
  end

  @doc "Combines flags into a bitfield."
  @spec from_list(kind(), [atom()]) :: integer()
  def from_list(kind, flags), do: Enum.reduce(flags, 0, &bor(&2, bit(kind, &1)))

  defp bit(kind, flag), do: 1 <<< Keyword.fetch!(Map.fetch!(@flags, kind), flag)

  defp int(nil), do: 0
  defp int(bitfield) when is_binary(bitfield), do: String.to_integer(bitfield)
  defp int(bitfield) when is_integer(bitfield), do: bitfield
end
