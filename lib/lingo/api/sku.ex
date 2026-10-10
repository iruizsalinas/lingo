defmodule Lingo.Api.SKU do
  @moduledoc """
  SKUs and their subscriptions.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client

  @doc "Lists the application's SKUs."
  @spec list() :: Api.result([map()])
  def list do
    Client.app(fn application_id ->
      Client.request(:get, "/applications/#{application_id}/skus")
    end)
  end

  @doc "Lists the subscriptions to a SKU."
  @spec list_subscriptions(Api.id(), keyword()) :: Api.result([map()])
  def list_subscriptions(sku_id, opts \\ []) do
    params =
      Client.params(opts)

    Client.request(:get, "/skus/#{sku_id}/subscriptions", params: params)
  end

  @doc "Fetches a subscription to a SKU."
  @spec get_subscription(Api.id(), Api.id()) :: Api.result(map())
  def get_subscription(sku_id, subscription_id) do
    Client.request(:get, "/skus/#{sku_id}/subscriptions/#{subscription_id}")
  end
end
