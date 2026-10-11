defmodule Lingo.Api.Ban do
  @moduledoc """
  Guild bans.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.Ban

  @doc "Lists a guild's bans."
  @spec list(Api.id(), keyword()) :: Api.result([Ban.t()])
  def list(guild_id, opts \\ []) do
    params =
      Client.params(opts)

    Client.request(:get, "/guilds/#{guild_id}/bans", params: params) |> Client.into(&Ban.new/1)
  end

  @doc "Fetches the ban for a user."
  @spec get(Api.id(), Api.id()) :: Api.result(Ban.t())
  def get(guild_id, user_id) do
    Client.request(:get, "/guilds/#{guild_id}/bans/#{user_id}") |> Client.into(&Ban.new/1)
  end

  @doc "Bans a user. Pass `delete_message_seconds:` to also delete their recent messages."
  @spec create(Api.id(), Api.id(), keyword()) :: Api.result()
  def create(guild_id, user_id, opts \\ []) do
    json =
      case Keyword.get(opts, :delete_message_seconds) do
        nil -> %{}
        seconds -> %{delete_message_seconds: seconds}
      end

    Client.request(:put, "/guilds/#{guild_id}/bans/#{user_id}", json: json, reason: opts[:reason])
  end

  @doc "Lifts a user's ban."
  @spec delete(Api.id(), Api.id(), keyword()) :: Api.result()
  def delete(guild_id, user_id, opts \\ []) do
    Client.request(:delete, "/guilds/#{guild_id}/bans/#{user_id}", reason: opts[:reason])
  end

  @doc """
  Bans up to 200 users at once. Returns the ids Discord banned and those it
  couldn't, or that were already banned; Discord answers an error when it
  could ban none.
  """
  @spec bulk_create(Api.id(), [Api.id()], keyword()) ::
          Api.result(%{banned_users: [Api.id()], failed_users: [Api.id()]})
  def bulk_create(guild_id, user_ids, opts \\ []) when is_list(user_ids) do
    json = %{user_ids: user_ids}

    json =
      case Keyword.get(opts, :delete_message_seconds) do
        nil -> json
        seconds -> Map.put(json, :delete_message_seconds, seconds)
      end

    Client.request(:post, "/guilds/#{guild_id}/bulk-ban", json: json, reason: opts[:reason])
    |> Client.into(fn data ->
      %{banned_users: data["banned_users"] || [], failed_users: data["failed_users"] || []}
    end)
  end
end
