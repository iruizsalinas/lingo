defmodule Lingo.Helper.Member do
  @moduledoc """
  What the bot can do to a member, and how members are shown.

  Answered from the cache, which needs guilds, channels, roles and the bot's
  own user and member enabled (see `Lingo.Cache`). Anything missing gives
  `false`, `0` or `nil`.
  """

  alias Lingo.Cache
  alias Lingo.Helper.PermissionData, as: Data

  @doc "Whether the bot outranks a member, so it can change their nickname or roles. Nobody outranks the owner."
  def manageable?(guild_id, user_id) do
    guild = Cache.Guild.get(guild_id)
    me = Cache.User.get_current()

    cond do
      is_nil(guild) or is_nil(me) ->
        false

      user_id == me.id ->
        false

      guild.owner_id == user_id ->
        false

      guild.owner_id == me.id ->
        true

      true ->
        bot_member = Data.bot_member(guild_id)
        target = Cache.Member.get(guild_id, user_id)

        if bot_member && target do
          Data.highest_position(guild_id, bot_member) >
            Data.highest_position(guild_id, target)
        else
          false
        end
    end
  end

  @doc "Whether the bot can kick a member."
  def kickable?(guild_id, user_id) do
    manageable?(guild_id, user_id) and Data.bot_has_permission?(guild_id, :kick_members)
  end

  @doc "Whether the bot can ban a member."
  def bannable?(guild_id, user_id) do
    manageable?(guild_id, user_id) and Data.bot_has_permission?(guild_id, :ban_members)
  end

  @doc "A member's guild-wide permissions bitfield, or `0` when required data is missing."
  def permissions(guild_id, user_id) do
    case fetch_permissions(guild_id, user_id) do
      {:ok, permissions} -> permissions
      {:error, _} -> 0
    end
  end

  @doc "Like `permissions/2`, but `{:ok, bitfield}`, or `{:error, {:missing_cache, resource}}` naming what isn't cached."
  @spec fetch_permissions(String.t(), String.t()) ::
          {:ok, non_neg_integer()} | {:error, {:missing_cache, atom()}}
  defdelegate fetch_permissions(guild_id, user_id), to: Data, as: :guild

  @doc "The name a member is shown with: nickname, then global name, then username."
  def display_name(guild_id, user_id) do
    member = Cache.Member.get(guild_id, user_id)

    cond do
      is_nil(member) -> nil
      member.nick -> member.nick
      member.user && member.user.global_name -> member.user.global_name
      member.user -> member.user.username
      true -> nil
    end
  end

  @doc "The color a member's name is shown in, from their highest colored role, or `0`."
  def display_color(guild_id, user_id) do
    member = Cache.Member.get(guild_id, user_id)

    if member do
      roles = Cache.Role.list(guild_id)
      role_ids = MapSet.new(member.roles)

      roles
      |> Enum.reduce({-1, 0}, fn role, {best_position, best_color} ->
        if role.color > 0 and role.id in role_ids and role.position > best_position do
          {role.position, role.color}
        else
          {best_position, best_color}
        end
      end)
      |> elem(1)
    else
      0
    end
  end
end
