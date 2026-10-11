defmodule Lingo.Api.Webhook do
  @moduledoc """
  Webhooks and the messages they send.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.{Body, Client}
  alias Lingo.Type.{Message, Webhook}

  @doc "Creates a webhook in a channel."
  @spec create(Api.id(), Api.params(), keyword()) :: Api.result(Webhook.t())
  def create(channel_id, params, opts \\ []) do
    Client.request(:post, "/channels/#{channel_id}/webhooks",
      json: params,
      reason: opts[:reason]
    )
    |> Client.into(&Webhook.new/1)
  end

  @doc "Lists a channel's webhooks."
  @spec list_channel(Api.id()) :: Api.result([Webhook.t()])
  def list_channel(channel_id) do
    Client.request(:get, "/channels/#{channel_id}/webhooks") |> Client.into(&Webhook.new/1)
  end

  @doc "Lists a guild's webhooks."
  @spec list_guild(Api.id()) :: Api.result([Webhook.t()])
  def list_guild(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/webhooks") |> Client.into(&Webhook.new/1)
  end

  @doc "Fetches a webhook."
  @spec get(Api.id()) :: Api.result(Webhook.t())
  def get(webhook_id) do
    Client.request(:get, "/webhooks/#{webhook_id}") |> Client.into(&Webhook.new/1)
  end

  @doc "Fetches a webhook using its token instead of the bot's."
  @spec get_with_token(Api.id(), String.t()) :: Api.result(Webhook.t())
  def get_with_token(webhook_id, webhook_token) do
    Client.request(:get, "/webhooks/#{webhook_id}/#{webhook_token}")
    |> Client.into(&Webhook.new/1)
  end

  @doc "Edits a webhook."
  @spec update(Api.id(), Api.params(), keyword()) :: Api.result(Webhook.t())
  def update(webhook_id, params, opts \\ []) do
    Client.request(:patch, "/webhooks/#{webhook_id}", json: params, reason: opts[:reason])
    |> Client.into(&Webhook.new/1)
  end

  @doc "Edits a webhook using its token."
  @spec update_with_token(Api.id(), String.t(), Api.params()) :: Api.result(Webhook.t())
  def update_with_token(webhook_id, webhook_token, params) do
    Client.request(:patch, "/webhooks/#{webhook_id}/#{webhook_token}", json: params)
    |> Client.into(&Webhook.new/1)
  end

  @doc "Deletes a webhook."
  @spec delete(Api.id(), keyword()) :: Api.result()
  def delete(webhook_id, opts \\ []) do
    Client.request(:delete, "/webhooks/#{webhook_id}", reason: opts[:reason])
  end

  @doc "Deletes a webhook using its token."
  @spec delete_with_token(Api.id(), String.t()) :: Api.result()
  def delete_with_token(webhook_id, webhook_token) do
    Client.request(:delete, "/webhooks/#{webhook_id}/#{webhook_token}")
  end

  @doc """
  Sends a Slack-formatted message through a webhook. Options: `:thread_id`
  and `:wait`.
  """
  @spec execute_slack(Api.id(), String.t(), Api.params(), keyword()) :: Api.result()
  def execute_slack(webhook_id, webhook_token, params, opts \\ []),
    do: execute_compatible(webhook_id, webhook_token, "slack", params, opts)

  @doc """
  Sends a GitHub event through a webhook. Options: `:thread_id` and `:wait`.
  """
  @spec execute_github(Api.id(), String.t(), Api.params(), keyword()) :: Api.result()
  def execute_github(webhook_id, webhook_token, params, opts \\ []),
    do: execute_compatible(webhook_id, webhook_token, "github", params, opts)

  # Discord documents no body for these, only success
  defp execute_compatible(webhook_id, webhook_token, kind, params, opts) do
    with {:ok, _body} <-
           Client.request(:post, "/webhooks/#{webhook_id}/#{webhook_token}/#{kind}",
             json: params,
             params: Client.params(opts)
           ),
         do: :ok
  end

  @doc "Sends a message through a webhook. Pass `wait: true` to get the message back."
  @spec execute(Api.id(), String.t(), Api.content(), keyword()) ::
          Api.result() | {:ok, Message.t()}
  def execute(webhook_id, webhook_token, params, opts \\ []) do
    query_params =
      Client.params(opts)

    req_opts = [params: query_params] ++ Body.opts(params)

    with {:ok, data} <-
           Client.request(:post, "/webhooks/#{webhook_id}/#{webhook_token}", req_opts) do
      if opts[:wait], do: {:ok, Message.new(data)}, else: :ok
    end
  end

  @doc "Fetches a message a webhook sent."
  @spec get_message(Api.id(), String.t(), Api.id(), keyword()) :: Api.result(Message.t())
  def get_message(webhook_id, webhook_token, message_id, opts \\ []) do
    params = Client.params(opts)

    Client.request(:get, "/webhooks/#{webhook_id}/#{webhook_token}/messages/#{message_id}",
      params: params
    )
    |> Client.into(&Message.new/1)
  end

  @doc "Edits a message a webhook sent."
  @spec update_message(Api.id(), String.t(), Api.id(), Api.content(), keyword()) ::
          Api.result(Message.t())
  def update_message(webhook_id, webhook_token, message_id, params, opts \\ []) do
    query_params =
      Client.params(opts)

    req_opts = [params: query_params] ++ Body.opts(params)

    Client.request(
      :patch,
      "/webhooks/#{webhook_id}/#{webhook_token}/messages/#{message_id}",
      req_opts
    )
    |> Client.into(&Message.new/1)
  end

  @doc "Deletes a message a webhook sent."
  @spec delete_message(Api.id(), String.t(), Api.id(), keyword()) :: Api.result()
  def delete_message(webhook_id, webhook_token, message_id, opts \\ []) do
    query_params = Client.params(opts)

    Client.request(:delete, "/webhooks/#{webhook_id}/#{webhook_token}/messages/#{message_id}",
      params: query_params
    )
  end
end
