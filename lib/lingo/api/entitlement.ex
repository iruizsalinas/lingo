defmodule Lingo.Api.Entitlement do
  @moduledoc """
  Entitlements: who has access to the application's SKUs.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.Entitlement

  @doc "Lists the application's entitlements."
  @spec list(keyword()) :: Api.result([Entitlement.t()])
  def list(opts \\ []) do
    Client.app(fn application_id ->
      params =
        Client.params(opts)
        |> normalize_params()

      Client.request(:get, "/applications/#{application_id}/entitlements", params: params)
      |> Client.into(&Entitlement.new/1)
    end)
  end

  @doc "Fetches an entitlement."
  @spec get(Api.id()) :: Api.result(Entitlement.t())
  def get(entitlement_id) do
    Client.app(fn application_id ->
      Client.request(
        :get,
        "/applications/#{application_id}/entitlements/#{entitlement_id}"
      )
      |> Client.into(&Entitlement.new/1)
    end)
  end

  @doc "Marks a one-time purchase entitlement as used."
  @spec consume(Api.id()) :: Api.result()
  def consume(entitlement_id) do
    Client.app(fn application_id ->
      Client.request(
        :post,
        "/applications/#{application_id}/entitlements/#{entitlement_id}/consume"
      )
    end)
  end

  @doc "Grants a test entitlement to a user or guild."
  @spec create_test(Api.params()) :: Api.result(Entitlement.t())
  def create_test(params) do
    Client.app(fn application_id ->
      Client.request(:post, "/applications/#{application_id}/entitlements", json: params)
      |> Client.into(&Entitlement.new/1)
    end)
  end

  @doc "Deletes a test entitlement."
  @spec delete_test(Api.id()) :: Api.result()
  def delete_test(entitlement_id) do
    Client.app(fn application_id ->
      Client.request(:delete, "/applications/#{application_id}/entitlements/#{entitlement_id}")
    end)
  end

  defp normalize_params(%{sku_ids: sku_ids} = params) when is_list(sku_ids) do
    %{params | sku_ids: Enum.join(sku_ids, ",")}
  end

  defp normalize_params(params), do: params
end
