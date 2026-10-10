defmodule Lingo.Helper.Role do
  @moduledoc """
  Whether the bot can manage a role, and how roles rank.

  Answered from the cache, which needs guilds, channels, roles and the bot's
  own user and member enabled (see `Lingo.Cache`). Anything missing gives
  `false`, `0` or `nil`.
  """

  alias Lingo.Cache
  alias Lingo.Helper.PermissionData, as: Data

  @doc """
  Whether the bot can edit or assign a role: it has Manage Roles, and the
  role is below its highest role, not `@everyone` and not managed by an
  integration.
  """
  def editable?(guild_id, role_id) do
    role = Cache.Role.get(guild_id, role_id)
    guild = Cache.Guild.get(guild_id)
    me = Cache.User.get_current()

    cond do
      is_nil(role) or is_nil(guild) or is_nil(me) -> false
      role.managed -> false
      role.id == guild_id -> false
      guild.owner_id == me.id -> true
      not Data.bot_has_permission?(guild_id, :manage_roles) -> false
      true -> Data.highest_position(guild_id, Data.bot_member(guild_id)) > role.position
    end
  end

  @doc "Compares two roles' positions in the hierarchy: `:gt`, `:lt` or `:eq`, or `nil` if either isn't cached."
  def compare(guild_id, role_id_a, role_id_b) do
    a = Cache.Role.get(guild_id, role_id_a)
    b = Cache.Role.get(guild_id, role_id_b)

    cond do
      is_nil(a) or is_nil(b) -> nil
      a.position > b.position -> :gt
      a.position < b.position -> :lt
      a.id > b.id -> :gt
      a.id < b.id -> :lt
      true -> :eq
    end
  end
end
