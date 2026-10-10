defmodule Lingo.Helper.PermissionData do
  @moduledoc false

  # What the helpers read from the cache: permissions computed from cached
  # guilds, roles, members and channels, and the bot's place in the hierarchy.

  alias Lingo.{Cache, Permissions}

  def guild(guild_id, user_id) do
    with {:ok, guild} <- cached(Cache.Guild.get(guild_id), :guild),
         {:ok, member} <- cached(Cache.Member.get(guild_id, user_id), :member) do
      if guild.owner_id == user_id do
        {:ok, Permissions.all_flags()}
      else
        with {:ok, roles} <- roles(guild_id, member.roles) do
          everyone = Enum.find(roles, &(&1.id == guild_id))
          {:ok, Permissions.compute(everyone.permissions, member.roles, roles)}
        end
      end
    end
  end

  def channel(channel_id, user_id) do
    with {:ok, channel} <- cached(Cache.Channel.get(channel_id), :channel),
         {:ok, guild} <- cached(Cache.Guild.get(channel.guild_id), :guild),
         {:ok, member} <- cached(Cache.Member.get(channel.guild_id, user_id), :member) do
      if guild.owner_id == user_id do
        {:ok, Permissions.all_flags()}
      else
        with {:ok, roles} <- roles(guild.id, member.roles) do
          everyone = Enum.find(roles, &(&1.id == guild.id))

          {:ok,
           Permissions.compute(
             everyone.permissions,
             member.roles,
             roles,
             channel.permission_overwrites || [],
             user_id
           )}
        end
      end
    end
  end

  def bot_member(guild_id) do
    if me = Cache.User.get_current(), do: Cache.Member.get(guild_id, me.id)
  end

  def bot_has_permission?(guild_id, permission) do
    with %{id: id} <- Cache.User.get_current(),
         {:ok, perms} <- guild(guild_id, id) do
      Permissions.has?(perms, :administrator) or Permissions.has?(perms, permission)
    else
      _ -> false
    end
  end

  # the position of a member's highest role, 0 for none
  def highest_position(_guild_id, nil), do: 0

  def highest_position(guild_id, member) do
    ids = MapSet.new(member.roles)

    guild_id
    |> Cache.Role.list()
    |> Enum.filter(&(&1.id in ids))
    |> Enum.map(& &1.position)
    |> Enum.max(fn -> 0 end)
  end

  defp roles(guild_id, ids) do
    Enum.reduce_while(Enum.uniq([guild_id | ids]), {:ok, []}, fn id, {:ok, roles} ->
      case cached(Cache.Role.get(guild_id, id), :role) do
        {:ok, role} -> {:cont, {:ok, [role | roles]}}
        error -> {:halt, error}
      end
    end)
  end

  defp cached(nil, resource), do: {:error, {:missing_cache, resource}}
  defp cached(value, _), do: {:ok, value}
end
