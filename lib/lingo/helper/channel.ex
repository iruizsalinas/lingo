defmodule Lingo.Helper.Channel do
  @moduledoc """
  What the bot can do in a channel.

  Answered from the cache, so the guilds, roles, members and channels
  involved must be cached (the default); anything missing gives `false` or
  `nil`.
  """

  alias Lingo.{Cache, Permissions}

  @doc "A member's effective permissions bitfield in a channel, with overwrites applied, or `nil`."
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

  @doc "Whether the bot can see a channel."
  def viewable?(channel_id) do
    me = Cache.get_current_user()
    if me, do: Permissions.has?(permissions_for(channel_id, me.id), :view_channel), else: false
  end

  @doc "Whether the bot can manage a channel."
  def manageable?(channel_id) do
    me = Cache.get_current_user()

    if me do
      perms = permissions_for(channel_id, me.id)
      Permissions.has?(perms, :view_channel) and Permissions.has?(perms, :manage_channels)
    else
      false
    end
  end

  @doc "Whether the bot can delete a message: its own, or anyone's with Manage Messages."
  def message_deletable?(channel_id, message_id) do
    me = Cache.get_current_user()
    msg = Cache.get_message(channel_id, message_id)

    cond do
      is_nil(me) or is_nil(msg) -> false
      msg.author && msg.author.id == me.id -> true
      true -> Permissions.has?(permissions_for(channel_id, me.id), :manage_messages)
    end
  end
end
