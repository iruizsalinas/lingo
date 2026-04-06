defmodule Lingo do
  @moduledoc false

  def child_spec(opts) do
    bot_module = Keyword.fetch!(opts, :bot)
    token = Keyword.fetch!(opts, :token)
    intents = Keyword.get(opts, :intents, [:guilds, :guild_messages])
    cache = Keyword.get(opts, :cache, [])
    sharding = Keyword.get(opts, :sharding, [])
    presence = Keyword.get(opts, :presence, [])

    if Keyword.has_key?(sharding, :ids) and not Keyword.has_key?(sharding, :count) do
      raise ArgumentError, ":sharding :ids requires an explicit :count"
    end

    %{
      id: __MODULE__,
      start:
        {Lingo.Supervisor, :start_link,
         [
           [
             token: token,
             bot_module: bot_module,
             intents: intents,
             cache: cache,
             sharding: sharding,
             presence: presence
           ]
         ]},
      type: :supervisor
    }
  end

  # Guilds
  def get_guild(guild_id, opts \\ []), do: Lingo.Api.Guild.get(guild_id, opts)

  def edit_guild(guild_id, params, opts \\ []),
    do: Lingo.Api.Guild.modify(guild_id, params, opts)

  def get_guild_preview(guild_id), do: Lingo.Api.Guild.get_preview(guild_id)
  def list_guild_voice_regions(guild_id), do: Lingo.Api.Guild.get_voice_regions(guild_id)
  def list_integrations(guild_id), do: Lingo.Api.Guild.get_integrations(guild_id)

  def delete_integration(guild_id, integration_id, opts \\ []),
    do: Lingo.Api.Guild.delete_integration(guild_id, integration_id, opts)

  def get_widget_settings(guild_id), do: Lingo.Api.Guild.get_widget_settings(guild_id)

  def edit_widget(guild_id, params, opts \\ []),
    do: Lingo.Api.Guild.modify_widget(guild_id, params, opts)

  def get_widget(guild_id), do: Lingo.Api.Guild.get_widget(guild_id)

  def get_widget_image(guild_id, opts \\ []),
    do: Lingo.Api.Guild.get_widget_image(guild_id, opts)

  def get_vanity_url(guild_id), do: Lingo.Api.Guild.get_vanity_url(guild_id)
  def get_welcome_screen(guild_id), do: Lingo.Api.Guild.get_welcome_screen(guild_id)

  def edit_welcome_screen(guild_id, params, opts \\ []),
    do: Lingo.Api.Guild.modify_welcome_screen(guild_id, params, opts)

  def get_onboarding(guild_id), do: Lingo.Api.Guild.get_onboarding(guild_id)

  def edit_onboarding(guild_id, params, opts \\ []),
    do: Lingo.Api.Guild.modify_onboarding(guild_id, params, opts)

  def get_prune_count(guild_id, opts \\ []), do: Lingo.Api.Guild.get_prune_count(guild_id, opts)

  def begin_prune(guild_id, params \\ %{}, opts \\ []),
    do: Lingo.Api.Guild.begin_prune(guild_id, params, opts)

  def get_audit_log(guild_id, opts \\ []), do: Lingo.Api.AuditLog.get(guild_id, opts)

  # Channels
  def list_channels(guild_id), do: Lingo.Api.Guild.get_channels(guild_id)

  def create_channel(guild_id, params, opts \\ []),
    do: Lingo.Api.Guild.create_channel(guild_id, params, opts)

  def reorder_channels(guild_id, positions),
    do: Lingo.Api.Guild.modify_channel_positions(guild_id, positions)

  # Members
  def get_member(guild_id, user_id), do: Lingo.Api.Member.get(guild_id, user_id)
  def list_members(guild_id, opts \\ []), do: Lingo.Api.Member.list(guild_id, opts)

  def search_members(guild_id, query, opts \\ []),
    do: Lingo.Api.Member.search(guild_id, query, opts)

  def edit_member(guild_id, user_id, params, opts \\ []),
    do: Lingo.Api.Member.modify(guild_id, user_id, params, opts)

  def edit_own_member(guild_id, params, opts \\ []),
    do: Lingo.Api.Member.modify_current(guild_id, params, opts)

  def kick_member(guild_id, user_id, opts \\ []),
    do: Lingo.Api.Member.kick(guild_id, user_id, opts)

  def add_member_role(guild_id, user_id, role_id, opts \\ []),
    do: Lingo.Api.Member.add_role(guild_id, user_id, role_id, opts)

  def remove_member_role(guild_id, user_id, role_id, opts \\ []),
    do: Lingo.Api.Member.remove_role(guild_id, user_id, role_id, opts)

  # Bans
  def list_bans(guild_id, opts \\ []), do: Lingo.Api.Ban.list(guild_id, opts)
  def get_ban(guild_id, user_id), do: Lingo.Api.Ban.get(guild_id, user_id)
  def ban_member(guild_id, user_id, opts \\ []), do: Lingo.Api.Ban.create(guild_id, user_id, opts)

  def unban_member(guild_id, user_id, opts \\ []),
    do: Lingo.Api.Ban.delete(guild_id, user_id, opts)

  def bulk_ban(guild_id, user_ids, opts \\ []),
    do: Lingo.Api.Ban.bulk_create(guild_id, user_ids, opts)

  # Roles
  def list_roles(guild_id), do: Lingo.Api.Role.list(guild_id)
  def get_role(guild_id, role_id), do: Lingo.Api.Role.get(guild_id, role_id)
  def create_role(guild_id, params, opts \\ []), do: Lingo.Api.Role.create(guild_id, params, opts)

  def edit_role(guild_id, role_id, params, opts \\ []),
    do: Lingo.Api.Role.modify(guild_id, role_id, params, opts)

  def delete_role(guild_id, role_id, opts \\ []),
    do: Lingo.Api.Role.delete(guild_id, role_id, opts)

  def reorder_roles(guild_id, positions, opts \\ []),
    do: Lingo.Api.Role.modify_positions(guild_id, positions, opts)

  def get_role_member_counts(guild_id), do: Lingo.Api.Role.get_member_counts(guild_id)

  def get_channel(channel_id), do: Lingo.Api.Channel.get(channel_id)

  def edit_channel(channel_id, params, opts \\ []),
    do: Lingo.Api.Channel.modify(channel_id, params, opts)

  def delete_channel(channel_id, opts \\ []), do: Lingo.Api.Channel.delete(channel_id, opts)

  def edit_channel_permissions(channel_id, overwrite_id, params, opts \\ []),
    do: Lingo.Api.Channel.edit_permissions(channel_id, overwrite_id, params, opts)

  def delete_channel_permissions(channel_id, overwrite_id, opts \\ []),
    do: Lingo.Api.Channel.delete_permission(channel_id, overwrite_id, opts)

  def follow_channel(channel_id, webhook_channel_id, opts \\ []),
    do: Lingo.Api.Channel.follow_announcement(channel_id, webhook_channel_id, opts)

  def trigger_typing(channel_id), do: Lingo.Api.Channel.trigger_typing(channel_id)

  # Messages
  def get_message(channel_id, message_id), do: Lingo.Api.Message.get(channel_id, message_id)
  def list_messages(channel_id, opts \\ []), do: Lingo.Api.Message.list(channel_id, opts)
  def send_message(channel_id, params), do: Lingo.Api.Message.create(channel_id, params)

  def edit_message(channel_id, message_id, params),
    do: Lingo.Api.Message.edit(channel_id, message_id, params)

  def delete_message(channel_id, message_id, opts \\ []),
    do: Lingo.Api.Message.delete(channel_id, message_id, opts)

  def bulk_delete_messages(channel_id, message_ids, opts \\ []),
    do: Lingo.Api.Message.bulk_delete(channel_id, message_ids, opts)

  def crosspost_message(channel_id, message_id),
    do: Lingo.Api.Message.crosspost(channel_id, message_id)

  def search_messages(guild_id, opts \\ []), do: Lingo.Api.Message.search(guild_id, opts)
  def list_pins(channel_id), do: Lingo.Api.Channel.get_pinned_messages(channel_id)

  def pin_message(channel_id, message_id, opts \\ []),
    do: Lingo.Api.Channel.pin_message(channel_id, message_id, opts)

  def unpin_message(channel_id, message_id, opts \\ []),
    do: Lingo.Api.Channel.unpin_message(channel_id, message_id, opts)

  # Reactions
  def add_reaction(channel_id, message_id, emoji),
    do: Lingo.Api.Reaction.create(channel_id, message_id, emoji)

  def remove_own_reaction(channel_id, message_id, emoji),
    do: Lingo.Api.Reaction.delete_own(channel_id, message_id, emoji)

  def remove_user_reaction(channel_id, message_id, emoji, user_id),
    do: Lingo.Api.Reaction.delete_user(channel_id, message_id, emoji, user_id)

  def list_reactions(channel_id, message_id, emoji, opts \\ []),
    do: Lingo.Api.Reaction.get_users(channel_id, message_id, emoji, opts)

  def remove_all_reactions(channel_id, message_id),
    do: Lingo.Api.Reaction.delete_all(channel_id, message_id)

  def remove_emoji_reactions(channel_id, message_id, emoji),
    do: Lingo.Api.Reaction.delete_all_for_emoji(channel_id, message_id, emoji)

  # Threads
  def list_active_threads(guild_id), do: Lingo.Api.Guild.list_active_threads(guild_id)

  def start_thread_from_message(channel_id, message_id, params, opts \\ []),
    do: Lingo.Api.Thread.start_from_message(channel_id, message_id, params, opts)

  def start_thread(channel_id, params, opts \\ []),
    do: Lingo.Api.Thread.start_without_message(channel_id, params, opts)

  def join_thread(channel_id), do: Lingo.Api.Thread.join(channel_id)
  def leave_thread(channel_id), do: Lingo.Api.Thread.leave(channel_id)
  def add_thread_member(channel_id, user_id), do: Lingo.Api.Thread.add_member(channel_id, user_id)

  def remove_thread_member(channel_id, user_id),
    do: Lingo.Api.Thread.remove_member(channel_id, user_id)

  def get_thread_member(channel_id, user_id, opts \\ []),
    do: Lingo.Api.Thread.get_member(channel_id, user_id, opts)

  def list_thread_members(channel_id, opts \\ []),
    do: Lingo.Api.Thread.list_members(channel_id, opts)

  def list_public_archived_threads(channel_id, opts \\ []),
    do: Lingo.Api.Thread.list_public_archived(channel_id, opts)

  def list_private_archived_threads(channel_id, opts \\ []),
    do: Lingo.Api.Thread.list_private_archived(channel_id, opts)

  def list_joined_private_archived_threads(channel_id, opts \\ []),
    do: Lingo.Api.Thread.list_joined_private_archived(channel_id, opts)

  # Interactions
  def create_interaction_response(interaction_id, token, type, data \\ nil),
    do: Lingo.Api.Interaction.create_response(interaction_id, token, type, data)

  def get_original_response(token),
    do: Lingo.Api.Interaction.get_original_response(Lingo.Config.application_id(), token)

  def edit_original_response(token, params),
    do: Lingo.Api.Interaction.edit_original_response(Lingo.Config.application_id(), token, params)

  def delete_original_response(token),
    do: Lingo.Api.Interaction.delete_original_response(Lingo.Config.application_id(), token)

  def create_followup(token, params),
    do: Lingo.Api.Interaction.create_followup(Lingo.Config.application_id(), token, params)

  def edit_followup(token, message_id, params),
    do:
      Lingo.Api.Interaction.edit_followup(
        Lingo.Config.application_id(),
        token,
        message_id,
        params
      )

  def get_followup(token, message_id),
    do: Lingo.Api.Interaction.get_followup(Lingo.Config.application_id(), token, message_id)

  def delete_followup(token, message_id),
    do: Lingo.Api.Interaction.delete_followup(Lingo.Config.application_id(), token, message_id)

  # Commands
  def register_commands(bot_module), do: Lingo.Command.Registry.sync(bot_module)

  def register_commands_to_guild(bot_module, guild_id),
    do: Lingo.Command.Registry.sync_to_guild(bot_module, guild_id)

  def get_global_command(command_id),
    do: Lingo.Api.Command.get_global(Lingo.Config.application_id(), command_id)

  def list_global_commands, do: Lingo.Api.Command.list_global(Lingo.Config.application_id())

  def create_global_command(params),
    do: Lingo.Api.Command.create_global(Lingo.Config.application_id(), params)

  def edit_global_command(command_id, params),
    do: Lingo.Api.Command.edit_global(Lingo.Config.application_id(), command_id, params)

  def delete_global_command(command_id),
    do: Lingo.Api.Command.delete_global(Lingo.Config.application_id(), command_id)

  def sync_global_commands(commands),
    do: Lingo.Api.Command.bulk_overwrite_global(Lingo.Config.application_id(), commands)

  def get_guild_command(guild_id, command_id),
    do: Lingo.Api.Command.get_guild(Lingo.Config.application_id(), guild_id, command_id)

  def list_guild_commands(guild_id),
    do: Lingo.Api.Command.list_guild(Lingo.Config.application_id(), guild_id)

  def create_guild_command(guild_id, params),
    do: Lingo.Api.Command.create_guild(Lingo.Config.application_id(), guild_id, params)

  def edit_guild_command(guild_id, command_id, params),
    do: Lingo.Api.Command.edit_guild(Lingo.Config.application_id(), guild_id, command_id, params)

  def delete_guild_command(guild_id, command_id),
    do: Lingo.Api.Command.delete_guild(Lingo.Config.application_id(), guild_id, command_id)

  def sync_guild_commands(guild_id, commands),
    do: Lingo.Api.Command.bulk_overwrite_guild(Lingo.Config.application_id(), guild_id, commands)

  def list_command_permissions(guild_id),
    do: Lingo.Api.Command.get_all_permissions(Lingo.Config.application_id(), guild_id)

  def get_command_permissions(guild_id, command_id),
    do: Lingo.Api.Command.get_permissions(Lingo.Config.application_id(), guild_id, command_id)

  # Users
  def get_me, do: Lingo.Api.User.get_current()
  def get_user(user_id), do: Lingo.Api.User.get(user_id)
  def edit_me(params), do: Lingo.Api.User.modify_current(params)
  def list_guilds(opts \\ []), do: Lingo.Api.User.get_guilds(opts)
  def leave_guild(guild_id), do: Lingo.Api.User.leave_guild(guild_id)
  def create_dm(user_id), do: Lingo.Api.User.create_dm(user_id)

  # Invites
  def list_invites(guild_id), do: Lingo.Api.Guild.get_invites(guild_id)
  def list_channel_invites(channel_id), do: Lingo.Api.Channel.get_invites(channel_id)

  def create_invite(channel_id, params \\ %{}, opts \\ []),
    do: Lingo.Api.Channel.create_invite(channel_id, params, opts)

  def get_invite(code, opts \\ []), do: Lingo.Api.Invite.get(code, opts)
  def delete_invite(code, opts \\ []), do: Lingo.Api.Invite.delete(code, opts)
  def get_invite_target_users(code), do: Lingo.Api.Invite.get_target_users(code)

  def set_invite_target_users(code, user_ids),
    do: Lingo.Api.Invite.set_target_users(code, user_ids)

  def get_invite_target_users_status(code),
    do: Lingo.Api.Invite.get_target_users_status(code)

  # Webhooks
  def create_webhook(channel_id, params, opts \\ []),
    do: Lingo.Api.Webhook.create(channel_id, params, opts)

  def list_channel_webhooks(channel_id), do: Lingo.Api.Webhook.get_channel_webhooks(channel_id)
  def list_guild_webhooks(guild_id), do: Lingo.Api.Webhook.get_guild_webhooks(guild_id)
  def get_webhook(webhook_id), do: Lingo.Api.Webhook.get(webhook_id)

  def get_webhook_with_token(webhook_id, token),
    do: Lingo.Api.Webhook.get_with_token(webhook_id, token)

  def edit_webhook(webhook_id, params, opts \\ []),
    do: Lingo.Api.Webhook.modify(webhook_id, params, opts)

  def edit_webhook_with_token(webhook_id, token, params),
    do: Lingo.Api.Webhook.modify_with_token(webhook_id, token, params)

  def delete_webhook(webhook_id, opts \\ []), do: Lingo.Api.Webhook.delete(webhook_id, opts)

  def delete_webhook_with_token(webhook_id, token),
    do: Lingo.Api.Webhook.delete_with_token(webhook_id, token)

  def execute_webhook(webhook_id, token, params, opts \\ []),
    do: Lingo.Api.Webhook.execute(webhook_id, token, params, opts)

  def execute_slack_webhook(webhook_id, token, params, opts \\ []),
    do: Lingo.Api.Webhook.execute_slack(webhook_id, token, params, opts)

  def execute_github_webhook(webhook_id, token, params, opts \\ []),
    do: Lingo.Api.Webhook.execute_github(webhook_id, token, params, opts)

  def get_webhook_message(webhook_id, token, message_id, opts \\ []),
    do: Lingo.Api.Webhook.get_message(webhook_id, token, message_id, opts)

  def edit_webhook_message(webhook_id, token, message_id, params, opts \\ []),
    do: Lingo.Api.Webhook.edit_message(webhook_id, token, message_id, params, opts)

  def delete_webhook_message(webhook_id, token, message_id, opts \\ []),
    do: Lingo.Api.Webhook.delete_message(webhook_id, token, message_id, opts)

  # Emojis
  def list_emojis(guild_id), do: Lingo.Api.Emoji.list(guild_id)
  def get_emoji(guild_id, emoji_id), do: Lingo.Api.Emoji.get(guild_id, emoji_id)

  def create_emoji(guild_id, params, opts \\ []),
    do: Lingo.Api.Emoji.create(guild_id, params, opts)

  def edit_emoji(guild_id, emoji_id, params, opts \\ []),
    do: Lingo.Api.Emoji.modify(guild_id, emoji_id, params, opts)

  def delete_emoji(guild_id, emoji_id, opts \\ []),
    do: Lingo.Api.Emoji.delete(guild_id, emoji_id, opts)

  def list_app_emojis, do: Lingo.Api.Emoji.list_application(Lingo.Config.application_id())

  def get_app_emoji(emoji_id),
    do: Lingo.Api.Emoji.get_application(Lingo.Config.application_id(), emoji_id)

  def create_app_emoji(params),
    do: Lingo.Api.Emoji.create_application(Lingo.Config.application_id(), params)

  def edit_app_emoji(emoji_id, params),
    do: Lingo.Api.Emoji.modify_application(Lingo.Config.application_id(), emoji_id, params)

  def delete_app_emoji(emoji_id),
    do: Lingo.Api.Emoji.delete_application(Lingo.Config.application_id(), emoji_id)

  # Stickers
  def get_sticker(sticker_id), do: Lingo.Api.Sticker.get(sticker_id)
  def list_sticker_packs, do: Lingo.Api.Sticker.list_packs()
  def get_sticker_pack(pack_id), do: Lingo.Api.Sticker.get_pack(pack_id)
  def list_guild_stickers(guild_id), do: Lingo.Api.Sticker.list_guild(guild_id)

  def get_guild_sticker(guild_id, sticker_id),
    do: Lingo.Api.Sticker.get_guild(guild_id, sticker_id)

  def create_guild_sticker(guild_id, params, opts \\ []),
    do: Lingo.Api.Sticker.create_guild(guild_id, params, opts)

  def edit_guild_sticker(guild_id, sticker_id, params, opts \\ []),
    do: Lingo.Api.Sticker.modify_guild(guild_id, sticker_id, params, opts)

  def delete_guild_sticker(guild_id, sticker_id, opts \\ []),
    do: Lingo.Api.Sticker.delete_guild(guild_id, sticker_id, opts)

  # Scheduled Events
  def list_scheduled_events(guild_id, opts \\ []),
    do: Lingo.Api.ScheduledEvent.list(guild_id, opts)

  def get_scheduled_event(guild_id, event_id, opts \\ []),
    do: Lingo.Api.ScheduledEvent.get(guild_id, event_id, opts)

  def create_scheduled_event(guild_id, params, opts \\ []),
    do: Lingo.Api.ScheduledEvent.create(guild_id, params, opts)

  def edit_scheduled_event(guild_id, event_id, params, opts \\ []),
    do: Lingo.Api.ScheduledEvent.modify(guild_id, event_id, params, opts)

  def delete_scheduled_event(guild_id, event_id),
    do: Lingo.Api.ScheduledEvent.delete(guild_id, event_id)

  def list_scheduled_event_users(guild_id, event_id, opts \\ []),
    do: Lingo.Api.ScheduledEvent.get_users(guild_id, event_id, opts)

  # Stage Instances
  def create_stage(params, opts \\ []), do: Lingo.Api.StageInstance.create(params, opts)
  def get_stage(channel_id), do: Lingo.Api.StageInstance.get(channel_id)

  def edit_stage(channel_id, params, opts \\ []),
    do: Lingo.Api.StageInstance.modify(channel_id, params, opts)

  def delete_stage(channel_id, opts \\ []), do: Lingo.Api.StageInstance.delete(channel_id, opts)

  # Auto Moderation
  def list_automod_rules(guild_id), do: Lingo.Api.AutoModeration.list_rules(guild_id)

  def get_automod_rule(guild_id, rule_id),
    do: Lingo.Api.AutoModeration.get_rule(guild_id, rule_id)

  def create_automod_rule(guild_id, params, opts \\ []),
    do: Lingo.Api.AutoModeration.create_rule(guild_id, params, opts)

  def edit_automod_rule(guild_id, rule_id, params, opts \\ []),
    do: Lingo.Api.AutoModeration.modify_rule(guild_id, rule_id, params, opts)

  def delete_automod_rule(guild_id, rule_id, opts \\ []),
    do: Lingo.Api.AutoModeration.delete_rule(guild_id, rule_id, opts)

  # Templates
  def get_guild_template(code), do: Lingo.Api.Template.get(code)
  def list_guild_templates(guild_id), do: Lingo.Api.Template.list(guild_id)
  def create_guild_template(guild_id, params), do: Lingo.Api.Template.create(guild_id, params)
  def sync_guild_template(guild_id, code), do: Lingo.Api.Template.sync(guild_id, code)

  def edit_guild_template(guild_id, code, params),
    do: Lingo.Api.Template.modify(guild_id, code, params)

  def delete_guild_template(guild_id, code), do: Lingo.Api.Template.delete(guild_id, code)

  # Entitlements
  def list_entitlements(opts \\ []),
    do: Lingo.Api.Entitlement.list(Lingo.Config.application_id(), opts)

  def get_entitlement(entitlement_id),
    do: Lingo.Api.Entitlement.get(Lingo.Config.application_id(), entitlement_id)

  def consume_entitlement(entitlement_id),
    do: Lingo.Api.Entitlement.consume(Lingo.Config.application_id(), entitlement_id)

  def create_test_entitlement(params),
    do: Lingo.Api.Entitlement.create_test(Lingo.Config.application_id(), params)

  def delete_test_entitlement(entitlement_id),
    do: Lingo.Api.Entitlement.delete_test(Lingo.Config.application_id(), entitlement_id)

  # Application
  def get_application, do: Lingo.Api.Application.get_current()
  def edit_application(params), do: Lingo.Api.Application.modify_current(params)

  def get_role_connection_metadata,
    do: Lingo.Api.Application.get_role_connection_metadata(Lingo.Config.application_id())

  def edit_role_connection_metadata(params),
    do:
      Lingo.Api.Application.update_role_connection_metadata(Lingo.Config.application_id(), params)

  # Polls
  def list_poll_voters(channel_id, message_id, answer_id, opts \\ []),
    do: Lingo.Api.Poll.get_answer_voters(channel_id, message_id, answer_id, opts)

  def expire_poll(channel_id, message_id), do: Lingo.Api.Poll.expire(channel_id, message_id)

  # Voice
  def list_voice_regions, do: Lingo.Api.Voice.list_regions()
  def get_own_voice_state(guild_id), do: Lingo.Api.Voice.get_current_user_voice_state(guild_id)

  def get_voice_state(guild_id, user_id),
    do: Lingo.Api.Voice.get_user_voice_state(guild_id, user_id)

  def edit_own_voice_state(guild_id, params),
    do: Lingo.Api.Voice.modify_current_user_voice_state(guild_id, params)

  def edit_voice_state(guild_id, user_id, params),
    do: Lingo.Api.Voice.modify_user_voice_state(guild_id, user_id, params)

  # Soundboard
  def send_sound(channel_id, params), do: Lingo.Api.Soundboard.send_sound(channel_id, params)
  def list_default_sounds, do: Lingo.Api.Soundboard.list_defaults()
  def list_guild_sounds(guild_id), do: Lingo.Api.Soundboard.list_guild(guild_id)
  def get_guild_sound(guild_id, sound_id), do: Lingo.Api.Soundboard.get_guild(guild_id, sound_id)

  def create_guild_sound(guild_id, params, opts \\ []),
    do: Lingo.Api.Soundboard.create_guild(guild_id, params, opts)

  def edit_guild_sound(guild_id, sound_id, params, opts \\ []),
    do: Lingo.Api.Soundboard.modify_guild(guild_id, sound_id, params, opts)

  def delete_guild_sound(guild_id, sound_id, opts \\ []),
    do: Lingo.Api.Soundboard.delete_guild(guild_id, sound_id, opts)

  # SKUs
  def list_skus, do: Lingo.Api.SKU.list(Lingo.Config.application_id())
  def list_subscriptions(sku_id, opts \\ []), do: Lingo.Api.SKU.list_subscriptions(sku_id, opts)

  def get_subscription(sku_id, subscription_id),
    do: Lingo.Api.SKU.get_subscription(sku_id, subscription_id)

  # Cache
  def cached_guild(guild_id), do: Lingo.Cache.get_guild(guild_id)
  def cached_channel(channel_id), do: Lingo.Cache.get_channel(channel_id)
  def cached_user(user_id), do: Lingo.Cache.get_user(user_id)
  def cached_member(guild_id, user_id), do: Lingo.Cache.get_member(guild_id, user_id)
  def cached_message(channel_id, message_id), do: Lingo.Cache.get_message(channel_id, message_id)
  def cached_guilds, do: Lingo.Cache.list_guilds()
  def cached_voice_state(guild_id, user_id), do: Lingo.Cache.get_voice_state(guild_id, user_id)
  def cached_role(guild_id, role_id), do: Lingo.Cache.get_role(guild_id, role_id)
  def cached_roles(guild_id), do: Lingo.Cache.list_roles(guild_id)
  def cached_presence(guild_id, user_id), do: Lingo.Cache.get_presence(guild_id, user_id)
  def cached_me, do: Lingo.Cache.get_current_user()

  # Gateway
  def update_presence(status, opts \\ []) do
    payload = Lingo.Gateway.Payload.presence_update(status, opts[:text], opts[:activity])
    Lingo.Gateway.ShardManager.broadcast(payload)
  end

  def request_guild_members(guild_id, opts \\ []) do
    payload = Lingo.Gateway.Payload.request_guild_members(guild_id, opts)
    Lingo.Gateway.ShardManager.send_to_guild_shard(guild_id, payload)
  end

  def join_voice(guild_id, channel_id, opts \\ []) do
    payload = Lingo.Gateway.Payload.voice_state_update(guild_id, channel_id, opts)
    Lingo.Gateway.ShardManager.send_to_guild_shard(guild_id, payload)
  end

  def leave_voice(guild_id) do
    payload = Lingo.Gateway.Payload.voice_state_update(guild_id, nil)
    Lingo.Gateway.ShardManager.send_to_guild_shard(guild_id, payload)
  end

  def request_soundboard_sounds(guild_ids) when is_list(guild_ids) do
    payload = Lingo.Gateway.Payload.request_soundboard_sounds(guild_ids)
    Lingo.Gateway.ShardManager.broadcast(payload)
  end

  def shard_for_guild(guild_id), do: Lingo.Gateway.ShardManager.shard_for_guild(guild_id)
  def shard_count, do: Lingo.Gateway.ShardManager.shard_count()
  def shard_status(shard_id), do: Lingo.Gateway.ShardManager.shard_status(shard_id)
  def shard_statuses, do: Lingo.Gateway.ShardManager.shard_statuses()
  def restart_shard(shard_id), do: Lingo.Gateway.ShardManager.restart_shard(shard_id)
  def reshard, do: Lingo.Gateway.ShardManager.reshard()
  def latency(shard_id), do: Lingo.Gateway.Heartbeat.latency(shard_id)
  def latencies, do: Lingo.Gateway.Heartbeat.latencies()

  # CDN
  defdelegate user_avatar(user), to: Lingo.CDN
  defdelegate default_avatar(user_id), to: Lingo.CDN
  defdelegate guild_icon(guild), to: Lingo.CDN
  defdelegate guild_splash(guild), to: Lingo.CDN
  defdelegate guild_banner(guild), to: Lingo.CDN
  defdelegate emoji_url(emoji_id, animated? \\ false), to: Lingo.CDN
  defdelegate sticker_url(sticker_id, format_type), to: Lingo.CDN

  # Permissions
  defdelegate has_permission?(bitfield, permission), to: Lingo.Permissions, as: :has?
  defdelegate has_all_permissions?(bitfield, permissions), to: Lingo.Permissions, as: :has_all?
  defdelegate has_any_permission?(bitfield, permissions), to: Lingo.Permissions, as: :has_any?
  defdelegate resolve_permissions(permissions), to: Lingo.Permissions, as: :resolve
  defdelegate permission_list(bitfield), to: Lingo.Permissions, as: :to_list

  defdelegate compute_permissions(
                everyone_perms,
                role_ids,
                roles,
                overwrites \\ [],
                member_id \\ nil
              ), to: Lingo.Permissions, as: :compute

  # Embeds
  defdelegate embed(opts), to: Lingo.Type.Embed, as: :build

  # Components
  defdelegate action_row(components), to: Lingo.Type.Component
  defdelegate button(opts), to: Lingo.Type.Component
  defdelegate string_select(custom_id, opts \\ []), to: Lingo.Type.Component
  defdelegate text_input(custom_id, label_or_opts \\ [], opts \\ []), to: Lingo.Type.Component
  defdelegate user_select(custom_id, opts \\ []), to: Lingo.Type.Component
  defdelegate role_select(custom_id, opts \\ []), to: Lingo.Type.Component
  defdelegate mentionable_select(custom_id, opts \\ []), to: Lingo.Type.Component
  defdelegate channel_select(custom_id, opts \\ []), to: Lingo.Type.Component

  # V2 message components
  defdelegate section(text_displays, accessory), to: Lingo.Type.Component
  defdelegate text_display(content), to: Lingo.Type.Component
  defdelegate thumbnail(url, opts \\ []), to: Lingo.Type.Component
  defdelegate media_gallery(items), to: Lingo.Type.Component
  defdelegate file(url, opts \\ []), to: Lingo.Type.Component
  defdelegate separator(opts \\ []), to: Lingo.Type.Component
  defdelegate container(components, opts \\ []), to: Lingo.Type.Component

  # Modal components
  defdelegate label(label_text, component, opts \\ []), to: Lingo.Type.Component
  defdelegate file_upload(custom_id, opts \\ []), to: Lingo.Type.Component
  defdelegate radio_group(custom_id, options, opts \\ []), to: Lingo.Type.Component
  defdelegate checkbox_group(custom_id, options, opts \\ []), to: Lingo.Type.Component
  defdelegate checkbox(custom_id, opts \\ []), to: Lingo.Type.Component

  # Component helpers
  defdelegate modal(custom_id, title, components), to: Lingo.Type.Component
  defdelegate gallery_item(url, opts \\ []), to: Lingo.Type.Component
  defdelegate unfurled_media(url), to: Lingo.Type.Component
  defdelegate select_option(label, value, opts \\ []), to: Lingo.Type.Component
  defdelegate default_value(id, type), to: Lingo.Type.Component
  defdelegate v2(), to: Lingo.Type.Component

  # Snowflakes
  defdelegate snowflake_timestamp(snowflake), to: Lingo.Type.Snowflake, as: :timestamp
  defdelegate snowflake_from_timestamp(datetime), to: Lingo.Type.Snowflake, as: :from_timestamp

  # Emoji
  defdelegate format_emoji(emoji), to: Lingo.Type.Emoji, as: :format

  # Helpers
  defdelegate role_editable?(guild_id, role_id), to: Lingo.Helpers
  defdelegate compare_role_positions(guild_id, role_id_a, role_id_b), to: Lingo.Helpers
  defdelegate member_manageable?(guild_id, user_id), to: Lingo.Helpers
  defdelegate member_kickable?(guild_id, user_id), to: Lingo.Helpers
  defdelegate member_bannable?(guild_id, user_id), to: Lingo.Helpers
  defdelegate member_permissions(guild_id, user_id), to: Lingo.Helpers
  defdelegate member_display_name(guild_id, user_id), to: Lingo.Helpers
  defdelegate member_display_color(guild_id, user_id), to: Lingo.Helpers
  defdelegate permissions_for(channel_id, user_id), to: Lingo.Helpers
  defdelegate channel_viewable?(channel_id), to: Lingo.Helpers
  defdelegate channel_manageable?(channel_id), to: Lingo.Helpers
  defdelegate message_deletable?(channel_id, message_id), to: Lingo.Helpers
  defdelegate message_url(guild_id, channel_id, message_id), to: Lingo.Helpers

  # Formatting
  defdelegate timestamp(datetime, style \\ :short_datetime), to: Lingo.Format
  defdelegate mention_user(id), to: Lingo.Format
  defdelegate mention_channel(id), to: Lingo.Format
  defdelegate mention_role(id), to: Lingo.Format

  # Collectors
  defdelegate await_component(message_id, opts \\ []), to: Lingo.Collector
  defdelegate await_reaction(channel_id, message_id, opts \\ []), to: Lingo.Collector
  defdelegate collect_reactions(channel_id, message_id, opts \\ []), to: Lingo.Collector
end
