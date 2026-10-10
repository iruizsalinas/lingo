defmodule Lingo.Gateway.Dispatcher.Member do
  @moduledoc false

  # Member and role events. Each parse/2 updates the cache and returns the
  # event's payload.

  alias Lingo.Cache
  alias Lingo.Cache.Store
  alias Lingo.Event.{GuildMemberRemove, GuildMembersChunk, GuildRoleDelete}
  alias Lingo.Type.Member

  def parse(:guild_member_add, data) do
    m = Member.new(data)
    Store.put_member(data["guild_id"], m)
    adjust_member_count(data["guild_id"], 1)
    m
  end

  def parse(:guild_member_update, data) do
    m = Member.new(data)
    old = Cache.Member.get(data["guild_id"], get_in(data, ["user", "id"]))
    Store.put_member(data["guild_id"], m)
    %{old: old, new: m}
  end

  def parse(:guild_member_remove, data) do
    event = GuildMemberRemove.new(data)
    user_id = event.user && event.user.id
    old = Cache.Member.get(event.guild_id, user_id)
    Store.delete_member(event.guild_id, user_id)
    adjust_member_count(event.guild_id, -1)
    %{event | old: old}
  end

  def parse(:guild_members_chunk, data) do
    chunk = GuildMembersChunk.new(data)
    guild_id = chunk.guild_id

    Store.put_all([:members, :users], chunk.members, fn m -> Store.put_member(guild_id, m) end)

    Store.put_all([:presences, :users], chunk.presences, fn p ->
      Store.put_presence(guild_id, p)
    end)

    chunk
  end

  def parse(:guild_role_create, data) do
    role = Lingo.Type.Role.new(Map.put(data["role"], "guild_id", data["guild_id"]))
    Store.put_role(data["guild_id"], role)
    role
  end

  def parse(:guild_role_update, data) do
    role = Lingo.Type.Role.new(Map.put(data["role"], "guild_id", data["guild_id"]))
    old = Cache.Role.get(data["guild_id"], role.id)
    Store.put_role(data["guild_id"], role)
    %{old: old, new: role}
  end

  def parse(:guild_role_delete, data) do
    event = GuildRoleDelete.new(data)
    old = Cache.Role.get(event.guild_id, event.role_id)
    Store.delete_role(event.guild_id, event.role_id)
    %{event | old: old}
  end

  def parse(_event, _data), do: :skip

  defp adjust_member_count(guild_id, delta) do
    case Cache.Guild.get(guild_id) do
      %{member_count: count} = guild when is_integer(count) ->
        Store.put_guild(%{guild | member_count: max(count + delta, 0)})

      _ ->
        :ok
    end
  end
end
