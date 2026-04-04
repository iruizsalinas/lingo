defmodule Lingo.Gateway.Dispatcher do
  @moduledoc false

  require Logger

  alias Lingo.Cache

  alias Lingo.Type.{
    Channel,
    Entitlement,
    Guild,
    Interaction,
    Member,
    Message,
    Presence,
    ReactionEvent,
    User
  }

  @spec dispatch(atom(), map()) :: :ok
  def dispatch(event, data) do
    parsed =
      try do
        update_and_parse(event, data)
      rescue
        e ->
          Logger.error("Dispatcher crash on #{event}: #{Exception.message(e)}")
          data
      end

    case Lingo.Collector.try_match(event, parsed) do
      :collected -> :ok
      :miss -> dispatch_to_bot(event, parsed)
    end

    :ok
  end

  # combined cache update + parse to avoid constructing structs twice

  defp update_and_parse(:guild_create, data) do
    guild = Guild.new(data)

    Enum.each(guild.channels, fn ch ->
      Cache.put_channel(%{ch | guild_id: guild.id})
    end)

    Enum.each(guild.members, fn m -> Cache.put_member(guild.id, m) end)
    Enum.each(guild.roles, fn r -> Cache.put_role(guild.id, r) end)

    Enum.each(data["voice_states"] || [], fn vs ->
      Cache.put_voice_state(
        guild.id,
        Lingo.Type.VoiceState.new(Map.put(vs, "guild_id", guild.id))
      )
    end)

    Enum.each(data["presences"] || [], fn p ->
      Cache.put_presence(guild.id, Presence.new(p))
    end)

    # strip nested collections before caching - they live in their own tables
    Cache.put_guild(%{guild | channels: [], members: [], roles: []})

    guild
  end

  defp update_and_parse(:guild_update, data) do
    guild = Guild.new(data)
    old = Cache.get_guild(guild.id)
    Enum.each(guild.roles, fn r -> Cache.put_role(guild.id, r) end)
    Cache.put_guild(%{guild | channels: [], members: [], roles: []})
    %{old: old, new: guild}
  end

  defp update_and_parse(:guild_delete, %{"unavailable" => true, "id" => id}) do
    if guild = Cache.get_guild(id) do
      Cache.put_guild(%{guild | unavailable: true})
    end

    %{id: id, unavailable: true}
  end

  defp update_and_parse(:guild_delete, %{"id" => id}) do
    old = Cache.get_guild(id)
    Cache.delete_guild(id)
    %{old: old, new: %{id: id, unavailable: false}}
  end

  defp update_and_parse(:channel_create, data) do
    ch = Channel.new(data)
    Cache.put_channel(ch)
    ch
  end

  defp update_and_parse(:channel_update, data) do
    ch = Channel.new(data)
    old = Cache.get_channel(ch.id)
    Cache.put_channel(ch)
    %{old: old, new: ch}
  end

  defp update_and_parse(:channel_delete, data) do
    ch = Channel.new(data)
    old = Cache.get_channel(data["id"])
    Cache.delete_channel(data["id"])
    %{old: old, new: ch}
  end

  defp update_and_parse(:thread_create, data) do
    ch = Channel.new(data)
    Cache.put_channel(ch)
    ch
  end

  defp update_and_parse(:thread_update, data) do
    ch = Channel.new(data)
    old = Cache.get_channel(ch.id)
    Cache.put_channel(ch)
    %{old: old, new: ch}
  end

  defp update_and_parse(:thread_delete, data) do
    ch = Channel.new(data)
    old = Cache.get_channel(data["id"])
    Cache.delete_channel(data["id"])
    %{old: old, new: ch}
  end

  defp update_and_parse(:thread_list_sync, data) do
    threads = Enum.map(data["threads"] || [], &Channel.new/1)
    Enum.each(threads, &Cache.put_channel/1)

    %{
      guild_id: data["guild_id"],
      channel_ids: data["channel_ids"],
      threads: threads,
      members: data["members"] || []
    }
  end

  defp update_and_parse(:guild_member_add, data) do
    m = Member.new(data)
    Cache.put_member(data["guild_id"], m)
    m
  end

  defp update_and_parse(:guild_member_update, data) do
    m = Member.new(data)
    old = Cache.get_member(data["guild_id"], get_in(data, ["user", "id"]))
    Cache.put_member(data["guild_id"], m)
    %{old: old, new: m}
  end

  defp update_and_parse(:guild_member_remove, data) do
    user_id = get_in(data, ["user", "id"])
    old = Cache.get_member(data["guild_id"], user_id)
    Cache.delete_member(data["guild_id"], user_id)
    %{old: old, new: %{guild_id: data["guild_id"], user: User.new(data["user"])}}
  end

  defp update_and_parse(:guild_members_chunk, data) do
    guild_id = data["guild_id"]
    members = Enum.map(data["members"] || [], &Member.new/1)
    Enum.each(members, fn m -> Cache.put_member(guild_id, m) end)

    %{
      guild_id: guild_id,
      members: members,
      chunk_index: data["chunk_index"],
      chunk_count: data["chunk_count"],
      not_found: data["not_found"],
      nonce: data["nonce"]
    }
  end

  defp update_and_parse(:guild_role_create, data) do
    role = Lingo.Type.Role.new(data["role"])
    Cache.put_role(data["guild_id"], role)
    role
  end

  defp update_and_parse(:guild_role_update, data) do
    role = Lingo.Type.Role.new(data["role"])
    old = Cache.get_role(data["guild_id"], role.id)
    Cache.put_role(data["guild_id"], role)
    %{old: old, new: role}
  end

  defp update_and_parse(:guild_role_delete, data) do
    old = Cache.get_role(data["guild_id"], data["role_id"])
    Cache.delete_role(data["guild_id"], data["role_id"])
    %{old: old, new: %{guild_id: data["guild_id"], role_id: data["role_id"]}}
  end

  defp update_and_parse(:guild_emojis_update, data) do
    emojis = Enum.map(data["emojis"] || [], &Lingo.Type.Emoji.new/1)
    guild = Cache.get_guild(data["guild_id"])
    old_emojis = if guild, do: guild.emojis || [], else: []

    if guild, do: Cache.put_guild(%{guild | emojis: emojis})

    %{
      old: %{guild_id: data["guild_id"], emojis: old_emojis},
      new: %{guild_id: data["guild_id"], emojis: emojis}
    }
  end

  defp update_and_parse(:guild_stickers_update, data) do
    stickers = Enum.map(data["stickers"] || [], &Lingo.Type.Sticker.new/1)
    guild = Cache.get_guild(data["guild_id"])
    old_stickers = if guild, do: guild.stickers || [], else: []

    if guild, do: Cache.put_guild(%{guild | stickers: stickers})

    %{
      old: %{guild_id: data["guild_id"], stickers: old_stickers},
      new: %{guild_id: data["guild_id"], stickers: stickers}
    }
  end

  defp update_and_parse(:guild_ban_add, data) do
    %{guild_id: data["guild_id"], user: User.new(data["user"])}
  end

  defp update_and_parse(:guild_ban_remove, data) do
    %{guild_id: data["guild_id"], user: User.new(data["user"])}
  end

  defp update_and_parse(:message_create, data) do
    msg = Message.new(data)
    Cache.put_message(msg)
    msg
  end

  # message_update can be partial, merge instead of replace
  defp update_and_parse(:message_update, data) do
    old = Cache.get_message(data["channel_id"], data["id"])
    Cache.merge_message(data["channel_id"], data)
    %{old: old, new: Message.new(data)}
  end

  defp update_and_parse(:message_delete, data) do
    old = Cache.get_message(data["channel_id"], data["id"])
    Cache.delete_message(data["channel_id"], data["id"])

    %{
      old: old,
      new: %{id: data["id"], channel_id: data["channel_id"], guild_id: data["guild_id"]}
    }
  end

  defp update_and_parse(:message_delete_bulk, data) do
    ids = data["ids"] || []
    Enum.each(ids, fn id -> Cache.delete_message(data["channel_id"], id) end)
    %{ids: ids, channel_id: data["channel_id"], guild_id: data["guild_id"]}
  end

  defp update_and_parse(:voice_state_update, data) do
    vs = Lingo.Type.VoiceState.new(data)
    old = Cache.get_voice_state(data["guild_id"], vs.user_id)
    Cache.put_voice_state(data["guild_id"], vs)
    %{old: old, new: vs}
  end

  defp update_and_parse(:presence_update, data) do
    p = Presence.new(data)
    old = Cache.get_presence(data["guild_id"], get_in(data, ["user", "id"]))
    Cache.put_presence(data["guild_id"], p)
    %{old: old, new: p}
  end

  defp update_and_parse(:user_update, data) do
    u = User.new(data)
    old = Cache.get_user(u.id)
    Cache.put_user(u)
    %{old: old, new: u}
  end

  defp update_and_parse(:ready, data) do
    if user_data = data["user"] do
      Cache.put_current_user(User.new(user_data))
    end

    data
  end

  # events that only need parsing, no cache update
  defp update_and_parse(:interaction_create, data), do: Interaction.new(data)
  defp update_and_parse(:message_reaction_add, data), do: ReactionEvent.new(data)
  defp update_and_parse(:message_reaction_remove, data), do: ReactionEvent.new(data)

  defp update_and_parse(:message_reaction_remove_all, data) do
    %{channel_id: data["channel_id"], message_id: data["message_id"], guild_id: data["guild_id"]}
  end

  defp update_and_parse(:message_reaction_remove_emoji, data), do: ReactionEvent.new(data)
  defp update_and_parse(:invite_create, data), do: Lingo.Type.Invite.new(data)

  defp update_and_parse(:invite_delete, data) do
    %{channel_id: data["channel_id"], guild_id: data["guild_id"], code: data["code"]}
  end

  defp update_and_parse(:stage_instance_create, data), do: Lingo.Type.StageInstance.new(data)
  defp update_and_parse(:stage_instance_update, data), do: Lingo.Type.StageInstance.new(data)
  defp update_and_parse(:stage_instance_delete, data), do: Lingo.Type.StageInstance.new(data)

  defp update_and_parse(:guild_scheduled_event_create, data),
    do: Lingo.Type.ScheduledEvent.new(data)

  defp update_and_parse(:guild_scheduled_event_update, data),
    do: Lingo.Type.ScheduledEvent.new(data)

  defp update_and_parse(:guild_scheduled_event_delete, data),
    do: Lingo.Type.ScheduledEvent.new(data)

  defp update_and_parse(:auto_moderation_rule_create, data),
    do: Lingo.Type.AutoModerationRule.new(data)

  defp update_and_parse(:auto_moderation_rule_update, data),
    do: Lingo.Type.AutoModerationRule.new(data)

  defp update_and_parse(:auto_moderation_rule_delete, data),
    do: Lingo.Type.AutoModerationRule.new(data)

  defp update_and_parse(:auto_moderation_action_execution, data), do: data

  defp update_and_parse(:guild_audit_log_entry_create, data),
    do: Lingo.Type.AuditLogEntry.new(data)

  defp update_and_parse(:entitlement_create, data), do: Entitlement.new(data)
  defp update_and_parse(:entitlement_update, data), do: Entitlement.new(data)
  defp update_and_parse(:entitlement_delete, data), do: Entitlement.new(data)
  defp update_and_parse(_event, data), do: data

  # forward to user's bot module

  defp dispatch_to_bot(:interaction_create, %Interaction{} = interaction) do
    Lingo.Command.Handler.handle_interaction(interaction)
  end

  defp dispatch_to_bot(event, data) do
    bot_module = Lingo.Config.bot_module()

    if bot_module && function_exported?(bot_module, :__handle_event__, 2) do
      Task.start(fn ->
        bot_module.__handle_event__(event, data)
      end)
    end
  end
end
