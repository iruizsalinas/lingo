defmodule Lingo.Gateway.Dispatcher.Guild do
  @moduledoc false

  # GUILD_* events: guilds, their emojis, stickers and bans. Each parse/2 updates the cache and
  # returns what the bot's handle_event/2 receives.

  alias Lingo.Cache
  alias Lingo.Cache.Store

  alias Lingo.Type.{Channel, Guild, Presence, User}

  def parse(:guild_create, data) do
    guild = Guild.new(data)

    Enum.each(guild.channels, fn ch ->
      Store.put_channel(%{ch | guild_id: guild.id})
    end)

    # active threads arrive separately from channels
    Enum.each(data["threads"] || [], fn thread ->
      Store.put_channel(Channel.new(Map.put(thread, "guild_id", guild.id)))
    end)

    Enum.each(guild.members, fn m -> Store.put_member(guild.id, m) end)
    Enum.each(guild.roles, fn r -> Store.put_role(guild.id, %{r | guild_id: guild.id}) end)

    Enum.each(data["voice_states"] || [], fn vs ->
      Store.put_voice_state(
        guild.id,
        Lingo.Type.VoiceState.new(Map.put(vs, "guild_id", guild.id))
      )
    end)

    Enum.each(data["presences"] || [], fn p ->
      Store.put_presence(guild.id, Presence.new(Map.put(p, "guild_id", guild.id)))
    end)

    # strip nested collections before caching - they live in their own tables
    Store.put_guild(%{guild | channels: [], members: [], roles: []})

    guild
  end

  def parse(:guild_update, data) do
    old = Cache.get_guild(data["id"])
    guild = data |> Guild.new() |> keep_guild_create_fields(old)
    Enum.each(guild.roles, fn r -> Store.put_role(guild.id, %{r | guild_id: guild.id}) end)
    Store.put_guild(%{guild | channels: [], members: [], roles: []})
    %{old: old, new: guild}
  end

  def parse(:guild_delete, %{"unavailable" => true, "id" => id}) do
    if guild = Cache.get_guild(id) do
      Store.put_guild(%{guild | unavailable: true})
    end

    %{id: id, unavailable: true}
  end

  def parse(:guild_delete, %{"id" => id}) do
    old = Cache.get_guild(id)
    Store.delete_guild(id)
    %{old: old, new: %{id: id, unavailable: false}}
  end

  def parse(:guild_emojis_update, data) do
    emojis = Enum.map(data["emojis"] || [], &Lingo.Type.Emoji.new/1)
    guild = Cache.get_guild(data["guild_id"])
    old_emojis = if guild, do: guild.emojis || [], else: []

    if guild, do: Store.put_guild(%{guild | emojis: emojis})

    %{
      old: %{guild_id: data["guild_id"], emojis: old_emojis},
      new: %{guild_id: data["guild_id"], emojis: emojis}
    }
  end

  def parse(:guild_stickers_update, data) do
    stickers = Enum.map(data["stickers"] || [], &Lingo.Type.Sticker.new/1)
    guild = Cache.get_guild(data["guild_id"])
    old_stickers = if guild, do: guild.stickers || [], else: []

    if guild, do: Store.put_guild(%{guild | stickers: stickers})

    %{
      old: %{guild_id: data["guild_id"], stickers: old_stickers},
      new: %{guild_id: data["guild_id"], stickers: stickers}
    }
  end

  def parse(:guild_ban_add, data) do
    %{guild_id: data["guild_id"], user: User.new(data["user"])}
  end

  def parse(:guild_ban_remove, data) do
    %{guild_id: data["guild_id"], user: User.new(data["user"])}
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
