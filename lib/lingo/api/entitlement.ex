defmodule Lingo.Api.Entitlement do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.Entitlement

  def list(application_id, opts \\ []) do
    params =
      opts
      |> Keyword.take([
        :user_id,
        :sku_ids,
        :before,
        :after,
        :limit,
        :guild_id,
        :exclude_ended,
        :exclude_deleted
      ])
      |> Enum.into(%{})

    with {:ok, data} <-
           Client.request(:get, "/applications/#{application_id}/entitlements", params: params) do
      {:ok, Enum.map(data, &Entitlement.new/1)}
    end
  end

  def get(application_id, entitlement_id) do
    with {:ok, data} <-
           Client.request(:get, "/applications/#{application_id}/entitlements/#{entitlement_id}") do
      {:ok, Entitlement.new(data)}
    end
  end

  def consume(application_id, entitlement_id) do
    Client.request(
      :post,
      "/applications/#{application_id}/entitlements/#{entitlement_id}/consume"
    )
  end

  def create_test(application_id, params) do
    with {:ok, data} <-
           Client.request(:post, "/applications/#{application_id}/entitlements", json: params) do
      {:ok, Entitlement.new(data)}
    end
  end

  def delete_test(application_id, entitlement_id) do
    Client.request(:delete, "/applications/#{application_id}/entitlements/#{entitlement_id}")
  end
end
