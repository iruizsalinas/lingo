defmodule Lingo.Gateway.Dispatcher.Guild do
  @moduledoc false

  # GUILD_* events that touch the cache: guilds, their emojis and stickers.
  # Each parse/2 updates the cache and returns the event's payload.

  alias Lingo.Cache
  alias Lingo.Cache.{Store, Tables}
  alias Lingo.Event.{GuildDelete, GuildEmojisUpdate, GuildStickersUpdate}
  alias Lingo.Type.Guild

  def parse(:guild_create, %{"id" => id, "unavailable" => true} = data) do
    guild = Guild.new(data)
    old = Cache.Guild.get(id)
    Store.put_guild(if old, do: %{old | unavailable: true}, else: guild)
    guild
  end

  def parse(:guild_create, data) do
    guild = Guild.new(data)
    prune_collections(guild.id, data)

    Store.put_all(:channels, guild.channels, fn ch ->
      Store.put_channel(%{ch | guild_id: guild.id})
    end)

    # active threads arrive separately from channels
    if Tables.enabled?(:channels) and Map.has_key?(data, "threads") do
      Lingo.Gateway.Dispatcher.Channel.parse(:thread_list_sync, %{
        "guild_id" => guild.id,
        "threads" => data["threads"]
      })
    end

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
    prune_collections(guild.id, data)
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

  # These lists are complete snapshots. Members and presences can be partial,
  # and cached archived threads do not belong to the channels snapshot.
  defp prune_collections(guild_id, data) do
    for {resource, id_field} <- [roles: "id", channels: "id", voice_states: "user_id"] do
      entries = data[Atom.to_string(resource)]

      if Tables.enabled?(resource) and is_list(entries) do
        ids = Map.new(entries, &{&1[id_field], true})
        missing = [{:not, {:is_map_key, :"$1", {:const, ids}}}]

        {head, guards} =
          if resource == :channels do
            non_threads =
              for type <- [:public_thread, :private_thread, :announcement_thread],
                  do: {:"=/=", :"$2", type}

            {{:"$1", %{guild_id: guild_id, type: :"$2"}}, missing ++ non_threads}
          else
            {{{guild_id, :"$1"}, :_}, missing}
          end

        Tables.select_delete(resource, [{head, guards, [true]}])
      end
    end
  end

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
