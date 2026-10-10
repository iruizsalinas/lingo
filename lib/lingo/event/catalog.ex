defmodule Lingo.Event.Catalog do
  @moduledoc false

  # Every event Lingo knows: Discord's name, the atom bots see, and the
  # payload. A payload is a module (its new/1 builds it), {:update, module}
  # for %{old: nil, new: module.new(data)}, or :internal for events only
  # Lingo uses. Names, parsing, the docs and the types all come from here.

  alias Lingo.Event, as: E
  alias Lingo.Type, as: T

  @gateway [
    {"READY", :ready, E.Ready},
    {"RESUMED", :resumed, E.Resumed},
    {"APPLICATION_COMMAND_PERMISSIONS_UPDATE", :application_command_permissions_update,
     T.CommandPermissions},
    {"AUTO_MODERATION_RULE_CREATE", :auto_moderation_rule_create, T.AutoModerationRule},
    {"AUTO_MODERATION_RULE_UPDATE", :auto_moderation_rule_update,
     {:update, T.AutoModerationRule}},
    {"AUTO_MODERATION_RULE_DELETE", :auto_moderation_rule_delete, T.AutoModerationRule},
    {"AUTO_MODERATION_ACTION_EXECUTION", :auto_moderation_action_execution,
     E.AutoModerationAction},
    {"CHANNEL_CREATE", :channel_create, T.Channel},
    {"CHANNEL_UPDATE", :channel_update, {:update, T.Channel}},
    {"CHANNEL_DELETE", :channel_delete, T.Channel},
    {"CHANNEL_INFO", :channel_info, E.ChannelInfo},
    {"CHANNEL_PINS_UPDATE", :channel_pins_update, E.ChannelPinsUpdate},
    {"THREAD_CREATE", :thread_create, T.Channel},
    {"THREAD_UPDATE", :thread_update, {:update, T.Channel}},
    {"THREAD_DELETE", :thread_delete, E.ThreadDelete},
    {"THREAD_LIST_SYNC", :thread_list_sync, E.ThreadListSync},
    {"THREAD_MEMBER_UPDATE", :thread_member_update, T.ThreadMember},
    {"THREAD_MEMBERS_UPDATE", :thread_members_update, E.ThreadMembersUpdate},
    {"ENTITLEMENT_CREATE", :entitlement_create, T.Entitlement},
    {"ENTITLEMENT_UPDATE", :entitlement_update, {:update, T.Entitlement}},
    {"ENTITLEMENT_DELETE", :entitlement_delete, T.Entitlement},
    {"GUILD_CREATE", :guild_create, T.Guild},
    {"GUILD_UPDATE", :guild_update, {:update, T.Guild}},
    {"GUILD_DELETE", :guild_delete, E.GuildDelete},
    {"GUILD_AUDIT_LOG_ENTRY_CREATE", :guild_audit_log_entry_create, T.AuditLogEntry},
    {"GUILD_BAN_ADD", :guild_ban_add, E.GuildBan},
    {"GUILD_BAN_REMOVE", :guild_ban_remove, E.GuildBan},
    {"GUILD_EMOJIS_UPDATE", :guild_emojis_update, E.GuildEmojisUpdate},
    {"GUILD_STICKERS_UPDATE", :guild_stickers_update, E.GuildStickersUpdate},
    {"GUILD_INTEGRATIONS_UPDATE", :guild_integrations_update, E.GuildIntegrationsUpdate},
    {"GUILD_MEMBER_ADD", :guild_member_add, T.Member},
    {"GUILD_MEMBER_UPDATE", :guild_member_update, {:update, T.Member}},
    {"GUILD_MEMBER_REMOVE", :guild_member_remove, E.GuildMemberRemove},
    {"GUILD_MEMBERS_CHUNK", :guild_members_chunk, E.GuildMembersChunk},
    {"GUILD_ROLE_CREATE", :guild_role_create, T.Role},
    {"GUILD_ROLE_UPDATE", :guild_role_update, {:update, T.Role}},
    {"GUILD_ROLE_DELETE", :guild_role_delete, E.GuildRoleDelete},
    {"GUILD_SCHEDULED_EVENT_CREATE", :guild_scheduled_event_create, T.ScheduledEvent},
    {"GUILD_SCHEDULED_EVENT_UPDATE", :guild_scheduled_event_update, {:update, T.ScheduledEvent}},
    {"GUILD_SCHEDULED_EVENT_DELETE", :guild_scheduled_event_delete, T.ScheduledEvent},
    {"GUILD_SCHEDULED_EVENT_USER_ADD", :guild_scheduled_event_user_add, E.ScheduledEventUser},
    {"GUILD_SCHEDULED_EVENT_USER_REMOVE", :guild_scheduled_event_user_remove,
     E.ScheduledEventUser},
    {"GUILD_SOUNDBOARD_SOUND_CREATE", :guild_soundboard_sound_create, T.SoundboardSound},
    {"GUILD_SOUNDBOARD_SOUND_UPDATE", :guild_soundboard_sound_update,
     {:update, T.SoundboardSound}},
    {"GUILD_SOUNDBOARD_SOUND_DELETE", :guild_soundboard_sound_delete, E.SoundboardSoundDelete},
    {"GUILD_SOUNDBOARD_SOUNDS_UPDATE", :guild_soundboard_sounds_update, E.SoundboardSounds},
    {"SOUNDBOARD_SOUNDS", :soundboard_sounds, E.SoundboardSounds},
    {"INTEGRATION_CREATE", :integration_create, T.Integration},
    {"INTEGRATION_UPDATE", :integration_update, {:update, T.Integration}},
    {"INTEGRATION_DELETE", :integration_delete, E.IntegrationDelete},
    {"INTERACTION_CREATE", :interaction_create, T.Interaction},
    {"INVITE_CREATE", :invite_create, T.Invite},
    {"INVITE_DELETE", :invite_delete, E.InviteDelete},
    {"MESSAGE_CREATE", :message_create, T.Message},
    {"MESSAGE_UPDATE", :message_update, {:update, T.Message}},
    {"MESSAGE_DELETE", :message_delete, E.MessageDelete},
    {"MESSAGE_DELETE_BULK", :message_delete_bulk, E.MessageDeleteBulk},
    {"MESSAGE_REACTION_ADD", :message_reaction_add, E.Reaction},
    {"MESSAGE_REACTION_REMOVE", :message_reaction_remove, E.Reaction},
    {"MESSAGE_REACTION_REMOVE_ALL", :message_reaction_remove_all, E.ReactionRemoveAll},
    {"MESSAGE_REACTION_REMOVE_EMOJI", :message_reaction_remove_emoji, E.Reaction},
    {"MESSAGE_POLL_VOTE_ADD", :message_poll_vote_add, E.PollVote},
    {"MESSAGE_POLL_VOTE_REMOVE", :message_poll_vote_remove, E.PollVote},
    {"PRESENCE_UPDATE", :presence_update, {:update, T.Presence}},
    {"RATE_LIMITED", :rate_limited, E.RateLimited},
    {"STAGE_INSTANCE_CREATE", :stage_instance_create, T.StageInstance},
    {"STAGE_INSTANCE_UPDATE", :stage_instance_update, {:update, T.StageInstance}},
    {"STAGE_INSTANCE_DELETE", :stage_instance_delete, T.StageInstance},
    {"SUBSCRIPTION_CREATE", :subscription_create, T.Subscription},
    {"SUBSCRIPTION_UPDATE", :subscription_update, {:update, T.Subscription}},
    {"SUBSCRIPTION_DELETE", :subscription_delete, T.Subscription},
    {"TYPING_START", :typing_start, E.TypingStart},
    {"USER_UPDATE", :user_update, {:update, T.User}},
    {"VOICE_CHANNEL_EFFECT_SEND", :voice_channel_effect_send, E.VoiceChannelEffect},
    {"VOICE_CHANNEL_STATUS_UPDATE", :voice_channel_status_update, E.VoiceChannelStatus},
    {"VOICE_CHANNEL_START_TIME_UPDATE", :voice_channel_start_time_update,
     E.VoiceChannelStartTime},
    {"VOICE_STATE_UPDATE", :voice_state_update, {:update, T.VoiceState}},
    {"VOICE_SERVER_UPDATE", :voice_server_update, :internal},
    {"WEBHOOKS_UPDATE", :webhooks_update, E.WebhooksUpdate}
  ]

  @webhook [
    {"APPLICATION_AUTHORIZED", :application_authorized, E.ApplicationAuthorized},
    {"APPLICATION_DEAUTHORIZED", :application_deauthorized, E.ApplicationDeauthorized},
    {"ENTITLEMENT_CREATE", :entitlement_create, T.Entitlement},
    {"ENTITLEMENT_UPDATE", :entitlement_update, {:update, T.Entitlement}},
    {"ENTITLEMENT_DELETE", :entitlement_delete, T.Entitlement},
    {"LOBBY_MESSAGE_CREATE", :lobby_message_create, T.LobbyMessage},
    {"LOBBY_MESSAGE_UPDATE", :lobby_message_update, {:update, T.LobbyMessage}},
    {"LOBBY_MESSAGE_DELETE", :lobby_message_delete, E.LobbyMessageDelete},
    {"GAME_DIRECT_MESSAGE_CREATE", :game_direct_message_create, T.Message},
    {"GAME_DIRECT_MESSAGE_UPDATE", :game_direct_message_update, {:update, T.Message}},
    {"GAME_DIRECT_MESSAGE_DELETE", :game_direct_message_delete, T.Message}
  ]

  @payloads Map.new(@gateway ++ @webhook, fn {_type, name, payload} -> {name, payload} end)

  @doc "Every event, as `{discord_type, name, payload}`, by where it comes from."
  def gateway, do: @gateway
  def webhook, do: @webhook

  @doc "The name of a gateway event, or `{:unknown, type}`."
  @spec gateway_name(String.t()) :: atom() | {:unknown, String.t()}
  def gateway_name(type), do: name(type, gateway_names())

  @doc "The name of a webhook event, or `{:unknown, type}`."
  @spec webhook_name(String.t()) :: atom() | {:unknown, String.t()}
  def webhook_name(type), do: name(type, webhook_names())

  @gateway_names Map.new(@gateway, fn {type, name, _} -> {type, name} end)
  @webhook_names Map.new(@webhook, fn {type, name, _} -> {type, name} end)
  defp gateway_names, do: @gateway_names
  defp webhook_names, do: @webhook_names

  defp name(type, names), do: Map.get(names, type, {:unknown, type})

  @doc "The declared payload of an event."
  @spec payload(atom()) :: module() | {:update, module()} | :internal | nil
  def payload(name), do: Map.get(@payloads, name)

  @doc """
  Builds an event's payload from Discord's data, without the cache: `old` is
  always `nil`. Unknown events become `Lingo.Event.Unknown`.
  """
  @spec parse(atom() | {:unknown, String.t()}, term()) :: term()
  def parse({:unknown, type}, data), do: Lingo.Event.Unknown.new(type, data)

  def parse(name, data) do
    case payload(name) do
      {:update, module} -> %{old: nil, new: module.new(data)}
      module when is_atom(module) and module not in [nil, :internal] -> module.new(data)
      _internal -> data
    end
  end
end
