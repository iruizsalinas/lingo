defmodule Lingo.Context.Resolved do
  @moduledoc false

  # Looking up the data Discord resolved for an interaction. Public through
  # Lingo.Context.

  alias Lingo.Context
  alias Lingo.Type.{Attachment, Channel, Member, Message, Role, User}

  @spec resolved_user(Context.t(), String.t()) :: User.t() | nil
  def resolved_user(ctx, user_id) do
    if data = lookup(ctx, "users", user_id), do: User.new(data)
  end

  @spec resolved_member(Context.t(), String.t()) :: Member.t() | nil
  def resolved_member(ctx, user_id) do
    if data = lookup(ctx, "members", user_id) do
      data
      |> put_user(ctx.resolved, user_id)
      |> put_guild_id(ctx.guild_id)
      |> Member.new()
    end
  end

  @spec resolved_role(Context.t(), String.t()) :: Role.t() | nil
  def resolved_role(ctx, role_id) do
    if data = lookup(ctx, "roles", role_id), do: data |> put_guild_id(ctx.guild_id) |> Role.new()
  end

  @spec resolved_channel(Context.t(), String.t()) :: Channel.t() | nil
  def resolved_channel(ctx, channel_id) do
    if data = lookup(ctx, "channels", channel_id),
      do: data |> put_guild_id(ctx.guild_id) |> Channel.new()
  end

  @spec resolved_message(Context.t(), String.t()) :: Message.t() | nil
  def resolved_message(ctx, message_id) do
    if data = lookup(ctx, "messages", message_id),
      do: data |> put_guild_id(ctx.guild_id) |> Message.new()
  end

  @spec resolved_attachment(Context.t(), String.t()) :: Attachment.t() | nil
  def resolved_attachment(ctx, attachment_id) do
    if data = lookup(ctx, "attachments", attachment_id), do: Attachment.new(data)
  end

  defp lookup(%Context{resolved: %{} = resolved}, kind, id), do: get_in(resolved, [kind, id])
  defp lookup(_ctx, _kind, _id), do: nil

  defp put_user(data, resolved, user_id) do
    case get_in(resolved, ["users", user_id]) do
      nil -> data
      user -> Map.put_new(data, "user", user)
    end
  end

  defp put_guild_id(data, nil), do: data
  defp put_guild_id(data, guild_id), do: Map.put_new(data, "guild_id", guild_id)
end
