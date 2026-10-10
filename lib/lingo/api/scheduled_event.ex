defmodule Lingo.Api.ScheduledEvent do
  @moduledoc """
  Guild scheduled events.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.ScheduledEvent

  @doc "Lists a guild's scheduled events."
  @spec list(Api.id(), keyword()) :: Api.result([ScheduledEvent.t()])
  def list(guild_id, opts \\ []) do
    params = Client.params(opts)

    Client.request(:get, "/guilds/#{guild_id}/scheduled-events", params: params)
    |> Client.into(&ScheduledEvent.new/1)
  end

  @doc "Fetches a scheduled event."
  @spec get(Api.id(), Api.id(), keyword()) :: Api.result(ScheduledEvent.t())
  def get(guild_id, event_id, opts \\ []) do
    params = Client.params(opts)

    Client.request(:get, "/guilds/#{guild_id}/scheduled-events/#{event_id}", params: params)
    |> Client.into(&ScheduledEvent.new/1)
  end

  @doc "Creates a scheduled event."
  @spec create(Api.id(), Api.params(), keyword()) :: Api.result(ScheduledEvent.t())
  def create(guild_id, params, opts \\ []) do
    Client.request(:post, "/guilds/#{guild_id}/scheduled-events",
      json: params,
      reason: opts[:reason]
    )
    |> Client.into(&ScheduledEvent.new/1)
  end

  @doc "Edits a scheduled event, including starting or ending it."
  @spec update(Api.id(), Api.id(), Api.params(), keyword()) :: Api.result(ScheduledEvent.t())
  def update(guild_id, event_id, params, opts \\ []) do
    Client.request(:patch, "/guilds/#{guild_id}/scheduled-events/#{event_id}",
      json: params,
      reason: opts[:reason]
    )
    |> Client.into(&ScheduledEvent.new/1)
  end

  @doc "Deletes a scheduled event."
  @spec delete(Api.id(), Api.id()) :: Api.result()
  def delete(guild_id, event_id) do
    Client.request(:delete, "/guilds/#{guild_id}/scheduled-events/#{event_id}")
  end

  @doc "Lists the users interested in a scheduled event."
  @spec list_users(Api.id(), Api.id(), keyword()) :: Api.result([map()])
  def list_users(guild_id, event_id, opts \\ []) do
    params =
      Client.params(opts)

    Client.request(:get, "/guilds/#{guild_id}/scheduled-events/#{event_id}/users", params: params)
  end
end
