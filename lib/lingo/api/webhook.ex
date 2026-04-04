defmodule Lingo.Api.Webhook do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.{Message, Webhook}

  def create(channel_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:post, "/channels/#{channel_id}/webhooks",
             json: params,
             reason: opts[:reason]
           ) do
      {:ok, Webhook.new(data)}
    end
  end

  def get_channel_webhooks(channel_id) do
    with {:ok, data} <- Client.request(:get, "/channels/#{channel_id}/webhooks") do
      {:ok, Enum.map(data, &Webhook.new/1)}
    end
  end

  def get_guild_webhooks(guild_id) do
    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/webhooks") do
      {:ok, Enum.map(data, &Webhook.new/1)}
    end
  end

  def get(webhook_id) do
    with {:ok, data} <- Client.request(:get, "/webhooks/#{webhook_id}") do
      {:ok, Webhook.new(data)}
    end
  end

  def get_with_token(webhook_id, webhook_token) do
    with {:ok, data} <- Client.request(:get, "/webhooks/#{webhook_id}/#{webhook_token}") do
      {:ok, Webhook.new(data)}
    end
  end

  def modify(webhook_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:patch, "/webhooks/#{webhook_id}", json: params, reason: opts[:reason]) do
      {:ok, Webhook.new(data)}
    end
  end

  def modify_with_token(webhook_id, webhook_token, params) do
    with {:ok, data} <-
           Client.request(:patch, "/webhooks/#{webhook_id}/#{webhook_token}", json: params) do
      {:ok, Webhook.new(data)}
    end
  end

  def delete(webhook_id, opts \\ []) do
    Client.request(:delete, "/webhooks/#{webhook_id}", reason: opts[:reason])
  end

  def delete_with_token(webhook_id, webhook_token) do
    Client.request(:delete, "/webhooks/#{webhook_id}/#{webhook_token}")
  end

  def execute_slack(webhook_id, webhook_token, params, opts \\ []) do
    query_params =
      opts
      |> Keyword.take([:wait, :thread_id])
      |> Enum.into(%{})

    Client.request(:post, "/webhooks/#{webhook_id}/#{webhook_token}/slack",
      json: params,
      params: query_params
    )
  end

  def execute_github(webhook_id, webhook_token, params, opts \\ []) do
    query_params =
      opts
      |> Keyword.take([:wait, :thread_id])
      |> Enum.into(%{})

    Client.request(:post, "/webhooks/#{webhook_id}/#{webhook_token}/github",
      json: params,
      params: query_params
    )
  end

  def execute(webhook_id, webhook_token, params, opts \\ []) when is_map(params) do
    query_params =
      opts
      |> Keyword.take([:wait, :thread_id])
      |> Enum.into(%{})

    {files, json} = Map.pop(params, :files)

    req_opts =
      if files do
        [multipart: build_multipart(json, files), params: query_params]
      else
        [json: json, params: query_params]
      end

    with {:ok, data} <-
           Client.request(:post, "/webhooks/#{webhook_id}/#{webhook_token}", req_opts) do
      if opts[:wait], do: {:ok, Message.new(data)}, else: :ok
    end
  end

  def get_message(webhook_id, webhook_token, message_id, opts \\ []) do
    params = if opts[:thread_id], do: %{thread_id: opts[:thread_id]}, else: nil

    with {:ok, data} <-
           Client.request(:get, "/webhooks/#{webhook_id}/#{webhook_token}/messages/#{message_id}",
             params: params
           ) do
      {:ok, Message.new(data)}
    end
  end

  def edit_message(webhook_id, webhook_token, message_id, params, opts \\ [])
      when is_map(params) do
    query_params = if opts[:thread_id], do: %{thread_id: opts[:thread_id]}, else: nil
    {files, json} = Map.pop(params, :files)

    req_opts =
      if files do
        [multipart: build_multipart(json, files), params: query_params]
      else
        [json: json, params: query_params]
      end

    with {:ok, data} <-
           Client.request(
             :patch,
             "/webhooks/#{webhook_id}/#{webhook_token}/messages/#{message_id}",
             req_opts
           ) do
      {:ok, Message.new(data)}
    end
  end

  def delete_message(webhook_id, webhook_token, message_id, opts \\ []) do
    query_params = if opts[:thread_id], do: %{thread_id: opts[:thread_id]}, else: nil

    Client.request(:delete, "/webhooks/#{webhook_id}/#{webhook_token}/messages/#{message_id}",
      params: query_params
    )
  end

  defp build_multipart(json, files), do: Client.build_multipart(json, files)
end
