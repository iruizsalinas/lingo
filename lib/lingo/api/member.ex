defmodule Lingo.Api.Member do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.Member

  def get(guild_id, user_id) do
    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/members/#{user_id}") do
      {:ok, new_member(data, guild_id)}
    end
  end

  def list(guild_id, opts \\ []) do
    params =
      opts
      |> Keyword.take([:limit, :after])
      |> Enum.into(%{})

    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/members", params: params) do
      {:ok, Enum.map(data, &new_member(&1, guild_id))}
    end
  end

  def search(guild_id, query, opts \\ []) do
    params =
      opts
      |> Keyword.take([:limit])
      |> Enum.into(%{query: query})

    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/members/search", params: params) do
      {:ok, Enum.map(data, &new_member(&1, guild_id))}
    end
  end

  def modify(guild_id, user_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:patch, "/guilds/#{guild_id}/members/#{user_id}",
             json: params,
             reason: opts[:reason]
           ) do
      {:ok, new_member(data, guild_id)}
    end
  end

  def modify_current(guild_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:patch, "/guilds/#{guild_id}/members/@me",
             json: params,
             reason: opts[:reason]
           ) do
      {:ok, new_member(data, guild_id)}
    end
  end

  def kick(guild_id, user_id, opts \\ []) do
    Client.request(:delete, "/guilds/#{guild_id}/members/#{user_id}", reason: opts[:reason])
  end

  def add_role(guild_id, user_id, role_id, opts \\ []) do
    Client.request(:put, "/guilds/#{guild_id}/members/#{user_id}/roles/#{role_id}",
      reason: opts[:reason]
    )
  end

  def remove_role(guild_id, user_id, role_id, opts \\ []) do
    Client.request(:delete, "/guilds/#{guild_id}/members/#{user_id}/roles/#{role_id}",
      reason: opts[:reason]
    )
  end

  defp new_member(data, guild_id) when is_map(data) do
    data
    |> Map.put("guild_id", guild_id)
    |> Member.new()
  end
end
