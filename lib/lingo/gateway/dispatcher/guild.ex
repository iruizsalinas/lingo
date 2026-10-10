defmodule Lingo.Gateway.Dispatcher.Guild do
  @moduledoc false

  # GUILD_* events that touch the cache: guilds, their emojis and stickers.
  # Each parse/2 updates the cache and returns the event's payload.

  alias Lingo.Cache
  alias Lingo.Cache.Store
  alias Lingo.Event.{GuildDelete, GuildEmojisUpdate, GuildStickersUpdate}
  alias Lingo.Type.{Channel, Guild}

  def parse(:guild_create, data) do
    guild = Guild.new(data)

    Store.put_all(:channels, guild.channels, fn ch ->
      Store.put_channel(%{ch | guild_id: guild.id})
    end)

    # active threads arrive separately from channels
    Store.put_all(:channels, data["threads"] || [], fn thread ->
      Store.put_channel(Channel.new(Map.put(thread, "guild_id", guild.id)))
    end)

    Store.put_all([:members, :users], guild.members, fn m -> Store.put_member(guild.id, m) end)
    Store.put_all(:roles, guild.roles, fn r -> Store.put_role(guild.id, r) end)

    Store.put_all(:voice_states, data["voice_states"] || [], fn vs ->
      Store.put_voice_state(
        guild.id,
        Lingo.Type.VoiceState.new(Map.put(vs, "guild_id", guild.id))
      )
    end)

    Store.put_all(
      [:presences, :users],
      data["presences"] || [],
      &Store.put_raw_presence(guild.id, &1)
    )

    # strip nested collections before caching - they live in their own tables
    Store.put_guild(guild)

    guild
  end

  def parse(:guild_update, data) do
    old = Cache.Guild.get(data["id"])
    guild = data |> Guild.new() |> keep_guild_create_fields(old)
    Store.put_all(:roles, guild.roles, fn r -> Store.put_role(guild.id, r) end)
    Store.put_guild(guild)
    %{old: old, new: guild}
  end

  # an unavailable guild is in an outage and comes back; otherwise the bot left
  def parse(:guild_delete, data) do
    event = GuildDelete.new(data)
    old = Cache.Guild.get(event.id)

    cond do
      not event.unavailable -> Store.delete_guild(event.id)
      old -> Store.put_guild(%{old | unavailable: true})
      true -> :ok
    end

    %{event | old: old}
  end

  def parse(:guild_emojis_update, data) do
    event = GuildEmojisUpdate.new(data)
    guild = Cache.Guild.get(event.guild_id)
    if guild, do: Store.put_guild(%{guild | emojis: event.emojis})
    %{event | old: guild && (guild.emojis || [])}
  end

  def parse(:guild_stickers_update, data) do
    event = GuildStickersUpdate.new(data)
    guild = Cache.Guild.get(event.guild_id)
    if guild, do: Store.put_guild(%{guild | stickers: event.stickers})
    %{event | old: guild && (guild.stickers || [])}
  end

  def parse(_event, _data), do: :skip

  # GUILD_UPDATE carries a plain guild object, without the GUILD_CREATE extras
  defp keep_guild_create_fields(guild, nil), do: guild

  defp keep_guild_create_fields(guild, old) do
    %{
      guild
      | joined_at: old.joined_at,
        large: old.large,
        member_count: old.member_count,
        unavailable: old.unavailable
    }
  end
end
