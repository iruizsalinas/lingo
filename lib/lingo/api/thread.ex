defmodule Lingo.Api.Thread do
  @moduledoc """
  Threads and forum posts.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.{Body, Client}
  alias Lingo.Type.Channel

  @doc "Starts a thread from a message."
  @spec start_from_message(Api.id(), Api.id(), Api.params(), keyword()) :: Api.result(Channel.t())
  def start_from_message(channel_id, message_id, params, opts \\ []) do
    Client.request(:post, "/channels/#{channel_id}/messages/#{message_id}/threads",
      json: params,
      reason: opts[:reason]
    )
    |> Client.into(&Channel.new/1)
  end

  @doc "Starts a thread without a message, or a forum post."
  @spec start_without_message(Api.id(), Api.params(), keyword()) :: Api.result(Channel.t())
  def start_without_message(channel_id, params, opts \\ []) do
    request_opts = [reason: opts[:reason]] ++ Body.opts(params)

    Client.request(:post, "/channels/#{channel_id}/threads", request_opts)
    |> Client.into(&Channel.new/1)
  end

  @doc "Adds the bot to a thread."
  @spec join(Api.id()) :: Api.result()
  def join(channel_id) do
    Client.request(:put, "/channels/#{channel_id}/thread-members/@me")
  end

  @doc "Removes the bot from a thread."
  @spec leave(Api.id()) :: Api.result()
  def leave(channel_id) do
    Client.request(:delete, "/channels/#{channel_id}/thread-members/@me")
  end

  @doc "Adds a member to a thread."
  @spec add_member(Api.id(), Api.id()) :: Api.result()
  def add_member(channel_id, user_id) do
    Client.request(:put, "/channels/#{channel_id}/thread-members/#{user_id}")
  end

  @doc "Removes a member from a thread."
  @spec remove_member(Api.id(), Api.id()) :: Api.result()
  def remove_member(channel_id, user_id) do
    Client.request(:delete, "/channels/#{channel_id}/thread-members/#{user_id}")
  end

  @doc "Fetches a thread member."
  @spec get_member(Api.id(), Api.id(), keyword()) :: Api.result(map())
  def get_member(channel_id, user_id, opts \\ []) do
    params = Client.params(opts)
    Client.request(:get, "/channels/#{channel_id}/thread-members/#{user_id}", params: params)
  end

  @doc "Lists a thread's members."
  @spec list_members(Api.id(), keyword()) :: Api.result([map()])
  def list_members(channel_id, opts \\ []) do
    params =
      Client.params(opts)

    Client.request(:get, "/channels/#{channel_id}/thread-members", params: params)
  end

  @doc "Lists a channel's archived public threads."
  @spec list_public_archived(Api.id(), keyword()) :: Api.result(map())
  def list_public_archived(channel_id, opts \\ []) do
    params =
      Client.params(opts)

    Client.request(:get, "/channels/#{channel_id}/threads/archived/public", params: params)
  end

  @doc "Lists a channel's archived private threads."
  @spec list_private_archived(Api.id(), keyword()) :: Api.result(map())
  def list_private_archived(channel_id, opts \\ []) do
    params =
      Client.params(opts)

    Client.request(:get, "/channels/#{channel_id}/threads/archived/private", params: params)
  end

  @doc "Lists archived private threads the bot has joined."
  @spec list_joined_private_archived(Api.id(), keyword()) :: Api.result(map())
  def list_joined_private_archived(channel_id, opts \\ []) do
    params =
      Client.params(opts)

    Client.request(:get, "/channels/#{channel_id}/users/@me/threads/archived/private",
      params: params
    )
  end
end
