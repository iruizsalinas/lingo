defmodule Lingo.Helper.Role do
  @moduledoc """
  Whether the bot can manage a role, and how roles rank.

  Answered from the cache, so the guilds, roles, members and channels
  involved must be explicitly enabled in the cache configuration. Caching is
  off by default. Anything missing gives `false` or
  `nil`.
  """

  alias Lingo.Cache
  alias Lingo.Helper.Member

  @doc """
  Whether the bot can edit or assign a role: it has Manage Roles, and the
  role is below its highest role, not `@everyone` and not managed by an
  integration.
  """
  def editable?(guild_id, role_id) do
    role = Cache.get_role(guild_id, role_id)
    guild = Cache.get_guild(guild_id)
    me = Cache.get_current_user()

    cond do
      is_nil(role) or is_nil(guild) or is_nil(me) -> false
      role.managed -> false
      role.id == guild_id -> false
      guild.owner_id == me.id -> true
      not Member.bot_has_permission?(guild_id, :manage_roles) -> false
      true -> highest_role_position(guild_id, Member.bot_member(guild_id)) > role.position
    end
  end

  @doc "Compares two roles' positions in the hierarchy: `:gt`, `:lt` or `:eq`, or `nil` if either isn't cached."
  def compare(guild_id, role_id_a, role_id_b) do
    a = Cache.get_role(guild_id, role_id_a)
    b = Cache.get_role(guild_id, role_id_b)

    cond do
      is_nil(a) or is_nil(b) -> nil
      a.position > b.position -> :gt
      a.position < b.position -> :lt
      a.id > b.id -> :gt
      a.id < b.id -> :lt
      true -> :eq
    end
  end

  @doc false
  def highest_role_position(_guild_id, nil), do: 0

  def highest_role_position(guild_id, member) do
    roles = Cache.list_roles(guild_id)
    role_ids = role_id_map(member.roles)

    Enum.reduce(roles, 0, fn role, max_position ->
      if Map.has_key?(role_ids, role.id) and role.position > max_position do
        role.position
      else
        max_position
      end
    end)
  end

  @doc false
  def role_id_map(role_ids) do
    Map.new(role_ids, &{&1, true})
  end
end
