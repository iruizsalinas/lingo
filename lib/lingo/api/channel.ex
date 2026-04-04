defmodule Lingo.Api.Channel do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.{Channel, Invite, Message}

  def get(channel_id) do
    with {:ok, data} <- Client.request(:get, "/channels/#{channel_id}") do
      {:ok, Channel.new(data)}
    end
  end

  def modify(channel_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:patch, "/channels/#{channel_id}", json: params, reason: opts[:reason]) do
      {:ok, Channel.new(data)}
    end
  end

  def delete(channel_id, opts \\ []) do
    with {:ok, data} <- Client.request(:delete, "/channels/#{channel_id}", reason: opts[:reason]) do
      {:ok, Channel.new(data)}
    end
  end

  def edit_permissions(channel_id, overwrite_id, params, opts \\ []) do
    Client.request(:put, "/channels/#{channel_id}/permissions/#{overwrite_id}",
      json: params,
      reason: opts[:reason]
    )
  end

  def delete_permission(channel_id, overwrite_id, opts \\ []) do
    Client.request(:delete, "/channels/#{channel_id}/permissions/#{overwrite_id}",
      reason: opts[:reason]
    )
  end

  def get_invites(channel_id) do
    with {:ok, data} <- Client.request(:get, "/channels/#{channel_id}/invites") do
      {:ok, Enum.map(data, &Invite.new/1)}
    end
  end

  def create_invite(channel_id, params \\ %{}, opts \\ []) do
    with {:ok, data} <-
           Client.request(:post, "/channels/#{channel_id}/invites",
             json: params,
             reason: opts[:reason]
           ) do
      {:ok, Invite.new(data)}
    end
  end

  def follow_announcement(channel_id, webhook_channel_id, opts \\ []) do
    Client.request(:post, "/channels/#{channel_id}/followers",
      json: %{webhook_channel_id: webhook_channel_id},
      reason: opts[:reason]
    )
  end

  def trigger_typing(channel_id) do
    Client.request(:post, "/channels/#{channel_id}/typing")
  end

  def get_pinned_messages(channel_id) do
    with {:ok, data} <- Client.request(:get, "/channels/#{channel_id}/messages/pins") do
      messages =
        (data["items"] || [])
        |> Enum.map(fn item -> Message.new(item["message"]) end)

      {:ok, messages}
    end
  end

  def pin_message(channel_id, message_id, opts \\ []) do
    Client.request(:put, "/channels/#{channel_id}/messages/pins/#{message_id}",
      reason: opts[:reason]
    )
  end

  def unpin_message(channel_id, message_id, opts \\ []) do
    Client.request(:delete, "/channels/#{channel_id}/messages/pins/#{message_id}",
      reason: opts[:reason]
    )
  end
end
