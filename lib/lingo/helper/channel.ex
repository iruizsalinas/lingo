defmodule Lingo.Helper.Channel do
  @moduledoc """
  What the bot can do in a channel.

  Answered from the cache, so the guilds, roles, members and channels
  involved must be cached (the default); anything missing gives `false` or
  `nil`.
  """

  alias Lingo.{Cache, Permissions}

  @doc "A member's channel permissions, or `0` when required data is missing."
  def permissions_for(channel_id, user_id) do
    case fetch_permissions_for(channel_id, user_id) do
      {:ok, permissions} -> permissions
      {:error, _} -> 0
    end
  end

  @doc "Channel permissions, or `{:error, {:missing_cache, resource}}` if required data is unavailable."
  @spec fetch_permissions_for(String.t(), String.t()) ::
          {:ok, non_neg_integer()} | {:error, {:missing_cache, atom()}}
  defdelegate fetch_permissions_for(channel_id, user_id),
    to: Lingo.Helper.PermissionData,
    as: :channel

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
