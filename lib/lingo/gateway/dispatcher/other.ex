defmodule Lingo.Gateway.Dispatcher.Other do
  @moduledoc false

  # Every other event Lingo parses. Each parse/2 updates the cache and
  # returns what the bot's handle_event/2 receives.

  alias Lingo.Cache
  alias Lingo.Cache.Store

  alias Lingo.Type.{Entitlement, Interaction, Presence, User}

  def parse(:voice_state_update, data) do
    vs = Lingo.Type.VoiceState.new(data)
    old = Cache.VoiceState.get(data["guild_id"], vs.user_id)
    Store.put_voice_state(data["guild_id"], vs)
    %{old: old, new: vs}
  end

  def parse(:presence_update, data) do
    p = Presence.new(data)
    user_id = get_in(data, ["user", "id"])
    old = Cache.Presence.get(data["guild_id"], user_id)
    Store.put_presence(data["guild_id"], p)
    new = Cache.Presence.get(data["guild_id"], user_id) || p
    %{old: old, new: new}
  end

  # USER_UPDATE is only sent for the current user

  def parse(:user_update, data) do
    u = User.new(data)
    old = Cache.User.get_current() || Cache.User.get(u.id)
    Store.put_user(u)
    Store.put_current_user(u)
    %{old: old, new: u}
  end

  def parse(:shard_ready, data) do
    if user_data = data["user"] do
      Store.put_current_user(User.new(user_data))
    end

    data
  end

  # events that only need parsing, no cache update

  def parse(:interaction_create, data), do: Interaction.new(data)

  def parse(:invite_create, data), do: Lingo.Type.Invite.new(data)

  def parse(:invite_delete, data) do
    %{channel_id: data["channel_id"], guild_id: data["guild_id"], code: data["code"]}
  end

  def parse(:stage_instance_create, data), do: Lingo.Type.StageInstance.new(data)

  def parse(:stage_instance_update, data), do: Lingo.Type.StageInstance.new(data)

  def parse(:stage_instance_delete, data), do: Lingo.Type.StageInstance.new(data)

  def parse(:guild_scheduled_event_create, data),
    do: Lingo.Type.ScheduledEvent.new(data)

  def parse(:guild_scheduled_event_update, data),
    do: Lingo.Type.ScheduledEvent.new(data)

  def parse(:guild_scheduled_event_delete, data),
    do: Lingo.Type.ScheduledEvent.new(data)

  def parse(:auto_moderation_rule_create, data),
    do: Lingo.Type.AutoModerationRule.new(data)

  def parse(:auto_moderation_rule_update, data),
    do: Lingo.Type.AutoModerationRule.new(data)

  def parse(:auto_moderation_rule_delete, data),
    do: Lingo.Type.AutoModerationRule.new(data)

  def parse(:auto_moderation_action_execution, data), do: data

  def parse(:guild_audit_log_entry_create, data),
    do: Lingo.Type.AuditLogEntry.new(data)

  def parse(:entitlement_create, data), do: Entitlement.new(data)

  def parse(:entitlement_update, data), do: Entitlement.new(data)

  def parse(:entitlement_delete, data), do: Entitlement.new(data)

  def parse(_event, _data), do: :skip
end
