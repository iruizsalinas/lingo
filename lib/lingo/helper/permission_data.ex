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
          base = Permissions.compute(everyone.permissions, member.roles, roles)

          if Permissions.has?(base, :administrator) do
            {:ok, base}
          else
            with {:ok, overwrites} <- channel_overwrites(channel) do
              {:ok,
               Permissions.compute(
                 everyone.permissions,
                 member.roles,
                 roles,
                 overwrites,
                 user_id
               )}
            end
          end
        end
      end
    end
  end

  defp channel_overwrites(%{type: type, parent_id: parent_id})
       when type in [:announcement_thread, :public_thread, :private_thread] do
    with {:ok, parent} <- cached(Cache.Channel.get(parent_id), :channel),
         do: {:ok, parent.permission_overwrites || []}
  end

  defp channel_overwrites(channel), do: {:ok, channel.permission_overwrites || []}

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

  def highest_role(_guild_id, nil), do: nil

  def highest_role(guild_id, member) do
    case roles(guild_id, member.roles) do
      {:ok, roles} ->
        Enum.reduce(roles, nil, fn role, highest ->
          if compare_roles(guild_id, role, highest) == :gt, do: role, else: highest
        end)

      {:error, _missing} ->
        nil
    end
  end

  def compare_roles(_guild_id, nil, nil), do: :eq
  def compare_roles(_guild_id, nil, _role), do: :lt
  def compare_roles(_guild_id, _role, nil), do: :gt

  def compare_roles(guild_id, a, b) do
    # Snowflakes are decimal strings: length then lexical order compares
    # their numeric values without losing precision. Older roles rank higher
    # when positions tie; @everyone always comes last.
    a_id = {byte_size(a.id), a.id}
    b_id = {byte_size(b.id), b.id}

    cond do
      a.id == b.id -> :eq
      a.id == guild_id -> :lt
      b.id == guild_id -> :gt
      a.position > b.position -> :gt
      a.position < b.position -> :lt
      a_id < b_id -> :gt
      true -> :lt
    end
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
