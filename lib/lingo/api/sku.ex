defmodule Lingo.Api.SKU do
  @moduledoc """
  SKUs and their subscriptions.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.{SKU, Subscription}

  @doc "Lists the application's SKUs."
  @spec list() :: Api.result([SKU.t()])
  def list do
    Client.app(fn application_id ->
      Client.request(:get, "/applications/#{application_id}/skus") |> Client.into(&SKU.new/1)
    end)
  end

  @doc "Lists the subscriptions to a SKU."
  @spec list_subscriptions(Api.id(), keyword()) :: Api.result([Subscription.t()])
  def list_subscriptions(sku_id, opts \\ []) do
    Client.request(:get, "/skus/#{sku_id}/subscriptions", params: Client.params(opts))
    |> Client.into(&Subscription.new/1)
  end

  @doc "Fetches a subscription to a SKU."
  @spec get_subscription(Api.id(), Api.id()) :: Api.result(Subscription.t())
  def get_subscription(sku_id, subscription_id) do
    Client.request(:get, "/skus/#{sku_id}/subscriptions/#{subscription_id}")
    |> Client.into(&Subscription.new/1)
  end
end
