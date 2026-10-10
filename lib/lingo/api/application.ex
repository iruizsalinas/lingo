defmodule Lingo.Api.Application do
  @moduledoc """
  The bot's application and its role connection metadata.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client

  @doc "Fetches the bot's application."
  @spec get_current() :: Api.result(map())
  def get_current do
    Client.request(:get, "/applications/@me")
  end

  @doc "Edits the bot's application."
  @spec update_current(Api.params()) :: Api.result(map())
  def update_current(params) do
    Client.request(:patch, "/applications/@me", json: params)
  end

  @doc "Fetches the application's role connection metadata."
  @spec get_role_connection_metadata() :: Api.result([map()])
  def get_role_connection_metadata do
    Client.app(fn application_id ->
      Client.request(:get, "/applications/#{application_id}/role-connections/metadata")
    end)
  end

  @doc "Replaces the application's role connection metadata."
  @spec update_role_connection_metadata(Api.params()) :: Api.result([map()])
  def update_role_connection_metadata(params) do
    Client.app(fn application_id ->
      Client.request(:put, "/applications/#{application_id}/role-connections/metadata",
        json: params
      )
    end)
  end
end
