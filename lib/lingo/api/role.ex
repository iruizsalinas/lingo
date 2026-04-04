defmodule Lingo.Api.Role do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.Role

  def list(guild_id) do
    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/roles") do
      {:ok, Enum.map(data, &Role.new/1)}
    end
  end

  def get(guild_id, role_id) do
    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/roles/#{role_id}") do
      {:ok, Role.new(data)}
    end
  end

  def create(guild_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:post, "/guilds/#{guild_id}/roles", json: params, reason: opts[:reason]) do
      {:ok, Role.new(data)}
    end
  end

  def modify(guild_id, role_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:patch, "/guilds/#{guild_id}/roles/#{role_id}",
             json: params,
             reason: opts[:reason]
           ) do
      {:ok, Role.new(data)}
    end
  end

  def delete(guild_id, role_id, opts \\ []) do
    Client.request(:delete, "/guilds/#{guild_id}/roles/#{role_id}", reason: opts[:reason])
  end

  def modify_positions(guild_id, positions, opts \\ []) do
    with {:ok, data} <-
           Client.request(:patch, "/guilds/#{guild_id}/roles",
             json: positions,
             reason: opts[:reason]
           ) do
      {:ok, Enum.map(data, &Role.new/1)}
    end
  end

  def get_member_counts(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/roles/member-counts")
  end
end
