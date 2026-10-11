defmodule Lingo.Api.Application do
  @moduledoc """
  The bot's application, its Activity instances and its role connection metadata.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.{ActivityInstance, Application, RoleConnectionMetadata}

  @doc "Fetches the bot's application."
  @spec get_current() :: Api.result(Application.t())
  def get_current do
    Client.request(:get, "/applications/@me") |> Client.into(&Application.new/1)
  end

  @doc "Edits the bot's application."
  @spec update_current(Api.params()) :: Api.result(Application.t())
  def update_current(params) do
    Client.request(:patch, "/applications/@me", json: params) |> Client.into(&Application.new/1)
  end

  @doc """
  Fetches a running instance of the app's Activity, with its `location`
  (guild and channel) and the `users` in it. Ended instances are 404s.
  """
  @spec get_activity_instance(String.t()) :: Api.result(ActivityInstance.t())
  def get_activity_instance(instance_id) do
    Client.app(fn application_id ->
      Client.request(:get, "/applications/#{application_id}/activity-instances/#{instance_id}")
      |> Client.into(&ActivityInstance.new/1)
    end)
  end

  @doc "Fetches the application's role connection metadata."
  @spec get_role_connection_metadata() :: Api.result([RoleConnectionMetadata.t()])
  def get_role_connection_metadata do
    Client.app(fn application_id ->
      Client.request(:get, "/applications/#{application_id}/role-connections/metadata")
      |> Client.into(&RoleConnectionMetadata.new/1)
    end)
  end

  @doc """
  Replaces the application's role connection metadata with a list of up to
  5 records, each with Discord's fields (`:type` as Discord's number, `:key`,
  `:name`, `:description`...).
  """
  @spec update_role_connection_metadata([Api.params()]) ::
          Api.result([RoleConnectionMetadata.t()])
  def update_role_connection_metadata(records) when is_list(records) do
    Client.app(fn application_id ->
      Client.request(:put, "/applications/#{application_id}/role-connections/metadata",
        json: Enum.map(records, &Map.new/1)
      )
      |> Client.into(&RoleConnectionMetadata.new/1)
    end)
  end
end
