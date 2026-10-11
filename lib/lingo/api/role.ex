defmodule Lingo.Api.Role do
  @moduledoc """
  Guild roles.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.Role

  @doc "Lists a guild's roles."
  @spec list(Api.id()) :: Api.result([Role.t()])
  def list(guild_id) do
    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/roles") do
      {:ok, Enum.map(data, &new_role(&1, guild_id))}
    end
  end

  @doc "Fetches a role."
  @spec get(Api.id(), Api.id()) :: Api.result(Role.t())
  def get(guild_id, role_id) do
    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/roles/#{role_id}") do
      {:ok, new_role(data, guild_id)}
    end
  end

  @doc "Creates a role."
  @spec create(Api.id(), Api.params(), keyword()) :: Api.result(Role.t())
  def create(guild_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:post, "/guilds/#{guild_id}/roles", json: params, reason: opts[:reason]) do
      {:ok, new_role(data, guild_id)}
    end
  end

  @doc "Edits a role."
  @spec update(Api.id(), Api.id(), Api.params(), keyword()) :: Api.result(Role.t())
  def update(guild_id, role_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:patch, "/guilds/#{guild_id}/roles/#{role_id}",
             json: params,
             reason: opts[:reason]
           ) do
      {:ok, new_role(data, guild_id)}
    end
  end

  @doc "Deletes a role."
  @spec delete(Api.id(), Api.id(), keyword()) :: Api.result()
  def delete(guild_id, role_id, opts \\ []) do
    Client.request(:delete, "/guilds/#{guild_id}/roles/#{role_id}", reason: opts[:reason])
  end

  @doc "Moves roles, from a list of `%{id:, position:}` maps."
  @spec update_positions(Api.id(), [map()], keyword()) :: Api.result([Role.t()])
  def update_positions(guild_id, positions, opts \\ []) do
    with {:ok, data} <-
           Client.request(:patch, "/guilds/#{guild_id}/roles",
             json: positions,
             reason: opts[:reason]
           ) do
      {:ok, Enum.map(data, &new_role(&1, guild_id))}
    end
  end

  @doc "Counts the members in each of a guild's roles, by role id, leaving out @everyone."
  @spec get_member_counts(Api.id()) :: Api.result(%{Api.id() => non_neg_integer()})
  def get_member_counts(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/roles/member-counts")
  end

  defp new_role(data, guild_id) when is_map(data) do
    data
    |> Map.put("guild_id", guild_id)
    |> Role.new()
  end
end
