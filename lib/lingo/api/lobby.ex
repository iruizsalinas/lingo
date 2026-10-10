defmodule Lingo.Api.Lobby do
  @moduledoc """
  Lobbies: groups of players for Discord's Social SDK, which a bot can create
  and manage, and link to a guild text channel.

  These are the endpoints a bot token may use; joining, leaving, linking and
  messaging as a player take the player's own OAuth2 token.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client

  @doc """
  Creates a lobby. Params: `:metadata` (string keys and values), `:members`
  (up to 25, each with an `:id` and optional `:metadata`, `:flags` and
  `:additional_name`) and `:idle_timeout_seconds` (5 to 604800).
  """
  @spec create(Api.params()) :: Api.result(map())
  def create(params \\ %{}), do: Client.request(:post, "/lobbies", json: params)

  @doc "Fetches a lobby."
  @spec get(Api.id()) :: Api.result(map())
  def get(lobby_id), do: Client.request(:get, "/lobbies/#{lobby_id}")

  @doc """
  Edits a lobby. `:members` replaces the whole member list, removing anyone
  left out.
  """
  @spec update(Api.id(), Api.params()) :: Api.result(map())
  def update(lobby_id, params), do: Client.request(:patch, "/lobbies/#{lobby_id}", json: params)

  @doc "Deletes a lobby; fine if it's already gone."
  @spec delete(Api.id()) :: Api.result()
  def delete(lobby_id), do: Client.request(:delete, "/lobbies/#{lobby_id}")

  @doc """
  Adds a member to a lobby, or edits one already in it. Params: `:metadata`,
  `:flags` (`1`: may link a channel) and `:additional_name`.
  """
  @spec update_member(Api.id(), Api.id(), Api.params()) :: Api.result(map())
  def update_member(lobby_id, user_id, params \\ %{}),
    do: Client.request(:put, "/lobbies/#{lobby_id}/members/#{user_id}", json: params)

  @doc """
  Adds, edits or removes up to 25 members at once. Each is a map with an
  `:id`, the fields of `update_member/3`, and `remove_member: true` to
  remove them. Returns the members added or edited.
  """
  @spec update_members(Api.id(), [map()]) :: Api.result([map()])
  def update_members(lobby_id, members) when is_list(members),
    do: Client.request(:post, "/lobbies/#{lobby_id}/members/bulk", json: members)

  @doc "Removes a member from a lobby; fine if they aren't in it."
  @spec delete_member(Api.id(), Api.id()) :: Api.result()
  def delete_member(lobby_id, user_id),
    do: Client.request(:delete, "/lobbies/#{lobby_id}/members/#{user_id}")

  @doc """
  Creates a single-use invite, valid for an hour, to the lobby's linked
  channel, for one of its members.
  """
  @spec create_invite(Api.id(), Api.id()) :: Api.result(map())
  def create_invite(lobby_id, user_id),
    do: Client.request(:post, "/lobbies/#{lobby_id}/members/#{user_id}/invites")

  @doc """
  Sets a lobby message's moderation metadata, sent on to game clients: up
  to 5 string keys and values.
  """
  @spec update_moderation_metadata(Api.id(), Api.id(), %{String.t() => String.t()}) ::
          Api.result()
  def update_moderation_metadata(lobby_id, message_id, metadata),
    do:
      Client.request(:put, "/lobbies/#{lobby_id}/messages/#{message_id}/moderation-metadata",
        json: metadata
      )
end
