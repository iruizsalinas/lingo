defmodule Lingo.Helper.PermissionData do
  @moduledoc false

  alias Lingo.{Cache, Permissions}

  def guild(guild_id, user_id) do
    with {:ok, guild} <- cached(Cache.get_guild(guild_id), :guild),
         {:ok, member} <- cached(Cache.get_member(guild_id, user_id), :member) do
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
    with {:ok, channel} <- cached(Cache.get_channel(channel_id), :channel),
         {:ok, guild} <- cached(Cache.get_guild(channel.guild_id), :guild),
         {:ok, member} <- cached(Cache.get_member(channel.guild_id, user_id), :member) do
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

  defp roles(guild_id, ids) do
    Enum.reduce_while(Enum.uniq([guild_id | ids]), {:ok, []}, fn id, {:ok, roles} ->
      case cached(Cache.get_role(guild_id, id), :role) do
        {:ok, role} -> {:cont, {:ok, [role | roles]}}
        error -> {:halt, error}
      end
    end)
  end

  defp cached(nil, resource), do: {:error, {:missing_cache, resource}}
  defp cached(value, _), do: {:ok, value}
end
