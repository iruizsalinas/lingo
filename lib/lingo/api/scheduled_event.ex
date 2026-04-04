defmodule Lingo.Api.ScheduledEvent do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.ScheduledEvent

  def list(guild_id, opts \\ []) do
    params = if opts[:with_user_count], do: %{with_user_count: true}, else: nil

    with {:ok, data} <-
           Client.request(:get, "/guilds/#{guild_id}/scheduled-events", params: params) do
      {:ok, Enum.map(data, &ScheduledEvent.new/1)}
    end
  end

  def get(guild_id, event_id, opts \\ []) do
    params = if opts[:with_user_count], do: %{with_user_count: true}, else: nil

    with {:ok, data} <-
           Client.request(:get, "/guilds/#{guild_id}/scheduled-events/#{event_id}",
             params: params
           ) do
      {:ok, ScheduledEvent.new(data)}
    end
  end

  def create(guild_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:post, "/guilds/#{guild_id}/scheduled-events",
             json: params,
             reason: opts[:reason]
           ) do
      {:ok, ScheduledEvent.new(data)}
    end
  end

  def modify(guild_id, event_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:patch, "/guilds/#{guild_id}/scheduled-events/#{event_id}",
             json: params,
             reason: opts[:reason]
           ) do
      {:ok, ScheduledEvent.new(data)}
    end
  end

  def delete(guild_id, event_id) do
    Client.request(:delete, "/guilds/#{guild_id}/scheduled-events/#{event_id}")
  end

  def get_users(guild_id, event_id, opts \\ []) do
    params =
      opts
      |> Keyword.take([:limit, :with_member, :before, :after])
      |> Enum.into(%{})

    Client.request(:get, "/guilds/#{guild_id}/scheduled-events/#{event_id}/users", params: params)
  end
end
