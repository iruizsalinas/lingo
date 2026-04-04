defmodule Lingo.Api.Ban do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.Ban

  def list(guild_id, opts \\ []) do
    params =
      opts
      |> Keyword.take([:limit, :before, :after])
      |> Enum.into(%{})

    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/bans", params: params) do
      {:ok, Enum.map(data, &Ban.new/1)}
    end
  end

  def get(guild_id, user_id) do
    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/bans/#{user_id}") do
      {:ok, Ban.new(data)}
    end
  end

  def create(guild_id, user_id, opts \\ []) do
    json =
      case Keyword.get(opts, :delete_message_seconds) do
        nil -> %{}
        seconds -> %{delete_message_seconds: seconds}
      end

    Client.request(:put, "/guilds/#{guild_id}/bans/#{user_id}", json: json, reason: opts[:reason])
  end

  def delete(guild_id, user_id, opts \\ []) do
    Client.request(:delete, "/guilds/#{guild_id}/bans/#{user_id}", reason: opts[:reason])
  end

  def bulk_create(guild_id, user_ids, opts \\ []) when is_list(user_ids) do
    json = %{user_ids: user_ids}

    json =
      case Keyword.get(opts, :delete_message_seconds) do
        nil -> json
        seconds -> Map.put(json, :delete_message_seconds, seconds)
      end

    Client.request(:post, "/guilds/#{guild_id}/bulk-ban", json: json, reason: opts[:reason])
  end
end
