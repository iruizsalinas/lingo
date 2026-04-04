defmodule Lingo.Helpers do
  @moduledoc false

  alias Lingo.{Cache, Permissions}

  # Role helpers

  def role_editable?(guild_id, role_id) do
    role = Cache.get_role(guild_id, role_id)
    guild = Cache.get_guild(guild_id)
    me = Cache.get_current_user()

    cond do
      is_nil(role) or is_nil(guild) or is_nil(me) -> false
      role.managed -> false
      role.id == guild_id -> false
      guild.owner_id == me.id -> true
      not bot_has_permission?(guild_id, :manage_roles) -> false
      true -> highest_role_position(guild_id, bot_member(guild_id)) > role.position
    end
  end

  def compare_role_positions(guild_id, role_id_a, role_id_b) do
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

  # Member helpers

  def member_manageable?(guild_id, user_id) do
    guild = Cache.get_guild(guild_id)
    me = Cache.get_current_user()

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
        bot_member = bot_member(guild_id)
        target = Cache.get_member(guild_id, user_id)

        if bot_member && target do
          highest_role_position(guild_id, bot_member) > highest_role_position(guild_id, target)
        else
          false
        end
    end
  end

  def member_kickable?(guild_id, user_id) do
    member_manageable?(guild_id, user_id) and bot_has_permission?(guild_id, :kick_members)
  end

  def member_bannable?(guild_id, user_id) do
    member_manageable?(guild_id, user_id) and bot_has_permission?(guild_id, :ban_members)
  end

  def member_permissions(guild_id, user_id) do
    guild = Cache.get_guild(guild_id)
    member = Cache.get_member(guild_id, user_id)

    cond do
      is_nil(guild) or is_nil(member) ->
        0

      guild.owner_id == user_id ->
        Permissions.resolve(Permissions.all_permissions())

      true ->
        roles = Cache.list_roles(guild_id)
        everyone = Enum.find(roles, fn r -> r.id == guild_id end)
        everyone_perms = if everyone, do: everyone.permissions, else: "0"
        Permissions.compute(everyone_perms, member.roles, roles)
    end
  end

  def member_display_name(guild_id, user_id) do
    member = Cache.get_member(guild_id, user_id)

    cond do
      is_nil(member) -> nil
      member.nick -> member.nick
      member.user && member.user.global_name -> member.user.global_name
      member.user -> member.user.username
      true -> nil
    end
  end

  def member_display_color(guild_id, user_id) do
    member = Cache.get_member(guild_id, user_id)

    if member do
      roles = Cache.list_roles(guild_id)

      member.roles
      |> Enum.map(fn rid -> Enum.find(roles, fn r -> r.id == rid end) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(fn r -> r.color > 0 end)
      |> Enum.sort_by(fn r -> r.position end, :desc)
      |> case do
        [top | _] -> top.color
        [] -> 0
      end
    else
      0
    end
  end

  # Channel helpers

  def permissions_for(channel_id, user_id) do
    channel = Cache.get_channel(channel_id)

    if channel && channel.guild_id do
      guild = Cache.get_guild(channel.guild_id)
      member = Cache.get_member(channel.guild_id, user_id)

      cond do
        is_nil(guild) or is_nil(member) ->
          0

        guild.owner_id == user_id ->
          Permissions.resolve(Permissions.all_permissions())

        true ->
          roles = Cache.list_roles(channel.guild_id)
          everyone = Enum.find(roles, fn r -> r.id == channel.guild_id end)
          everyone_perms = if everyone, do: everyone.permissions, else: "0"
          overwrites = channel.permission_overwrites || []

          Permissions.compute(everyone_perms, member.roles, roles, overwrites, user_id)
      end
    else
      0
    end
  end

  def channel_viewable?(channel_id) do
    me = Cache.get_current_user()
    if me, do: Permissions.has?(permissions_for(channel_id, me.id), :view_channel), else: false
  end

  def channel_manageable?(channel_id) do
    me = Cache.get_current_user()

    if me do
      perms = permissions_for(channel_id, me.id)
      Permissions.has?(perms, :view_channel) and Permissions.has?(perms, :manage_channels)
    else
      false
    end
  end

  # Message helpers

  def message_deletable?(channel_id, message_id) do
    me = Cache.get_current_user()
    msg = Cache.get_message(channel_id, message_id)

    cond do
      is_nil(me) or is_nil(msg) -> false
      msg.author && msg.author.id == me.id -> true
      true -> Permissions.has?(permissions_for(channel_id, me.id), :manage_messages)
    end
  end

  def message_url(guild_id, channel_id, message_id) do
    "https://discord.com/channels/#{guild_id}/#{channel_id}/#{message_id}"
  end

  # Internal helpers

  defp bot_member(guild_id) do
    me = Cache.get_current_user()
    if me, do: Cache.get_member(guild_id, me.id)
  end

  defp bot_has_permission?(guild_id, permission) do
    me = Cache.get_current_user()

    if me do
      perms = member_permissions(guild_id, me.id)
      Permissions.has?(perms, :administrator) or Permissions.has?(perms, permission)
    else
      false
    end
  end

  defp highest_role_position(guild_id, member) do
    roles = Cache.list_roles(guild_id)

    member.roles
    |> Enum.map(fn rid -> Enum.find(roles, fn r -> r.id == rid end) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.position)
    |> Enum.max(fn -> 0 end)
  end
end
