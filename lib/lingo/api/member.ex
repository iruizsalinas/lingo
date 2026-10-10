defmodule Lingo.Api.Member do
  @moduledoc """
  Guild members: fetching, editing, roles and kicks.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.Member

  @doc "Fetches a guild member."
  @spec get(Api.id(), Api.id()) :: Api.result(Member.t())
  def get(guild_id, user_id) do
    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/members/#{user_id}") do
      {:ok, new_member(data, guild_id)}
    end
  end

  @doc "Lists guild members, `limit:` at a time (needs the guild members intent)."
  @spec list(Api.id(), keyword()) :: Api.result([Member.t()])
  def list(guild_id, opts \\ []) do
    params =
      Client.params(opts)

    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/members", params: params) do
      {:ok, Enum.map(data, &new_member(&1, guild_id))}
    end
  end

  @doc """
  Adds a user to a guild with their OAuth2 token (`guilds.join` scope, see
  `Lingo.OAuth2`); the bot must be in the guild. Params: `:nick`, `:roles`,
  `:mute`, `:deaf`. Returns the member, or `:ok` when they were already in.
  """
  @spec create(Api.id(), Api.id(), String.t(), Api.params()) :: Api.result(Member.t()) | :ok
  def create(guild_id, user_id, access_token, params \\ []) do
    body = params |> Map.new() |> Map.put(:access_token, access_token)

    case Client.request(:put, "/guilds/#{guild_id}/members/#{user_id}", json: body) do
      {:ok, data} -> {:ok, new_member(data, guild_id)}
      other -> other
    end
  end

  @doc "Finds guild members whose username or nickname starts with `query`."
  @spec search(Api.id(), String.t(), keyword()) :: Api.result([Member.t()])
  def search(guild_id, query, opts \\ []) do
    params =
      opts
      |> Keyword.drop([:reason])
      |> Enum.into(%{query: query})

    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/members/search", params: params) do
      {:ok, Enum.map(data, &new_member(&1, guild_id))}
    end
  end

  @doc "Edits a guild member: nickname, roles, mute, deafen, timeout or voice channel."
  @spec update(Api.id(), Api.id(), Api.params(), keyword()) :: Api.result(Member.t())
  def update(guild_id, user_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:patch, "/guilds/#{guild_id}/members/#{user_id}",
             json: params,
             reason: opts[:reason]
           ) do
      {:ok, new_member(data, guild_id)}
    end
  end

  @doc """
  Edits the bot's own profile in a guild: `:nick`, and `:avatar`, `:banner`
  (images as data URIs) and `:bio`, shown in that guild only.
  """
  @spec update_current(Api.id(), Api.params(), keyword()) :: Api.result(Member.t())
  def update_current(guild_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:patch, "/guilds/#{guild_id}/members/@me",
             json: params,
             reason: opts[:reason]
           ) do
      {:ok, new_member(data, guild_id)}
    end
  end

  @doc "Removes a member from a guild."
  @spec kick(Api.id(), Api.id(), keyword()) :: Api.result()
  def kick(guild_id, user_id, opts \\ []) do
    Client.request(:delete, "/guilds/#{guild_id}/members/#{user_id}", reason: opts[:reason])
  end

  @doc "Gives a member a role."
  @spec add_role(Api.id(), Api.id(), Api.id(), keyword()) :: Api.result()
  def add_role(guild_id, user_id, role_id, opts \\ []) do
    Client.request(:put, "/guilds/#{guild_id}/members/#{user_id}/roles/#{role_id}",
      reason: opts[:reason]
    )
  end

  @doc "Takes a role away from a member."
  @spec remove_role(Api.id(), Api.id(), Api.id(), keyword()) :: Api.result()
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
