defmodule Lingo.Api.SKU do
  @moduledoc false

  alias Lingo.Api.Client

  def list(application_id) do
    Client.request(:get, "/applications/#{application_id}/skus")
  end

  def list_subscriptions(sku_id, opts \\ []) do
    params =
      opts
      |> Keyword.take([:before, :after, :limit, :user_id])
      |> Enum.into(%{})

    Client.request(:get, "/skus/#{sku_id}/subscriptions", params: params)
  end

  def get_subscription(sku_id, subscription_id) do
    Client.request(:get, "/skus/#{sku_id}/subscriptions/#{subscription_id}")
  end
end
