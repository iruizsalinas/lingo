defmodule Lingo.Helper.Channel do
  @moduledoc """
  What the bot can do in a channel.

  Answered from the cache, which needs guilds, channels, roles and the bot's
  own user and member enabled (see `Lingo.Cache`). Anything missing gives
  `false`, `0` or `nil`.
  """

  alias Lingo.{Cache, Permissions}

  @doc "A member's permissions bitfield in a channel, with overwrites applied, or `0` when data is missing."
  def permissions(channel_id, user_id) do
    case fetch_permissions(channel_id, user_id) do
      {:ok, permissions} -> permissions
      {:error, _} -> 0
    end
  end

  @doc "Like `permissions/2`, but `{:ok, bitfield}`, or `{:error, {:missing_cache, resource}}` naming what isn't cached."
  @spec fetch_permissions(String.t(), String.t()) ::
          {:ok, non_neg_integer()} | {:error, {:missing_cache, atom()}}
  defdelegate fetch_permissions(channel_id, user_id),
    to: Lingo.Helper.PermissionData,
    as: :channel

  @doc "Whether the bot can see a channel."
  def viewable?(channel_id) do
    me = Cache.User.get_current()
    if me, do: Permissions.has?(permissions(channel_id, me.id), :view_channel), else: false
  end

  @doc "Whether the bot can manage a channel."
  def manageable?(channel_id) do
    me = Cache.User.get_current()

    if me do
      perms = permissions(channel_id, me.id)
      Permissions.has?(perms, :view_channel) and Permissions.has?(perms, :manage_channels)
    else
      false
    end
  end

  @doc "Whether the bot can delete a message: its own, or anyone's with Manage Messages."
  def message_deletable?(channel_id, message_id) do
    me = Cache.User.get_current()
    msg = Cache.Message.get(channel_id, message_id)

    cond do
      is_nil(me) or is_nil(msg) -> false
      msg.author && msg.author.id == me.id -> true
      true -> Permissions.has?(permissions(channel_id, me.id), :manage_messages)
    end
  end
end
