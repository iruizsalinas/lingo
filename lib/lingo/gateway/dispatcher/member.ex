defmodule Lingo.Gateway.Dispatcher.Member do
  @moduledoc false

  # Member and role events. Each parse/2 updates the cache and
  # returns what the bot's handle_event/2 receives.

  alias Lingo.Cache
  alias Lingo.Cache.Store

  alias Lingo.Type.{Member, Presence, User}

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
    user_id = get_in(data, ["user", "id"])
    old = Cache.Member.get(data["guild_id"], user_id)
    Store.delete_member(data["guild_id"], user_id)
    adjust_member_count(data["guild_id"], -1)
    %{old: old, new: %{guild_id: data["guild_id"], user: User.new(data["user"])}}
  end

  def parse(:guild_members_chunk, data) do
    guild_id = data["guild_id"]

    members =
      Enum.map(data["members"] || [], fn member ->
        Member.new(Map.put(member, "guild_id", guild_id))
      end)

    presences =
      Enum.map(data["presences"] || [], fn presence ->
        Presence.new(Map.put(presence, "guild_id", guild_id))
      end)

    Store.put_all([:members, :users], members, fn m -> Store.put_member(guild_id, m) end)
    Store.put_all([:presences, :users], presences, fn p -> Store.put_presence(guild_id, p) end)

    %{
      guild_id: guild_id,
      members: members,
      presences: presences,
      chunk_index: data["chunk_index"],
      chunk_count: data["chunk_count"],
      not_found: data["not_found"],
      nonce: data["nonce"]
    }
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
    old = Cache.Role.get(data["guild_id"], data["role_id"])
    Store.delete_role(data["guild_id"], data["role_id"])
    %{old: old, new: %{guild_id: data["guild_id"], role_id: data["role_id"]}}
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
