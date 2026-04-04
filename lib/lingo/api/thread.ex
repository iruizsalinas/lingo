defmodule Lingo.Api.Thread do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.Channel

  def start_from_message(channel_id, message_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:post, "/channels/#{channel_id}/messages/#{message_id}/threads",
             json: params,
             reason: opts[:reason]
           ) do
      {:ok, Channel.new(data)}
    end
  end

  def start_without_message(channel_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:post, "/channels/#{channel_id}/threads",
             json: params,
             reason: opts[:reason]
           ) do
      {:ok, Channel.new(data)}
    end
  end

  def join(channel_id) do
    Client.request(:put, "/channels/#{channel_id}/thread-members/@me")
  end

  def leave(channel_id) do
    Client.request(:delete, "/channels/#{channel_id}/thread-members/@me")
  end

  def add_member(channel_id, user_id) do
    Client.request(:put, "/channels/#{channel_id}/thread-members/#{user_id}")
  end

  def remove_member(channel_id, user_id) do
    Client.request(:delete, "/channels/#{channel_id}/thread-members/#{user_id}")
  end

  def get_member(channel_id, user_id, opts \\ []) do
    params = if opts[:with_member], do: %{with_member: true}, else: nil
    Client.request(:get, "/channels/#{channel_id}/thread-members/#{user_id}", params: params)
  end

  def list_members(channel_id, opts \\ []) do
    params =
      opts
      |> Keyword.take([:with_member, :after, :limit])
      |> Enum.into(%{})

    Client.request(:get, "/channels/#{channel_id}/thread-members", params: params)
  end

  def list_public_archived(channel_id, opts \\ []) do
    params =
      opts
      |> Keyword.take([:before, :limit])
      |> Enum.into(%{})

    Client.request(:get, "/channels/#{channel_id}/threads/archived/public", params: params)
  end

  def list_private_archived(channel_id, opts \\ []) do
    params =
      opts
      |> Keyword.take([:before, :limit])
      |> Enum.into(%{})

    Client.request(:get, "/channels/#{channel_id}/threads/archived/private", params: params)
  end

  def list_joined_private_archived(channel_id, opts \\ []) do
    params =
      opts
      |> Keyword.take([:before, :limit])
      |> Enum.into(%{})

    Client.request(:get, "/channels/#{channel_id}/users/@me/threads/archived/private",
      params: params
    )
  end
end
