defmodule Lingo.Api.Voice do
  @moduledoc """
  Voice regions and voice states. To join voice channels, see `Lingo.Voice`.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client

  @doc "Lists Discord's voice regions."
  @spec list_regions() :: Api.result([map()])
  def list_regions do
    Client.request(:get, "/voice/regions")
  end

  @doc "Fetches the bot's voice state in a guild."
  @spec get_current_state(Api.id()) :: Api.result(map())
  def get_current_state(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/voice-states/@me")
  end

  @doc "Fetches a user's voice state in a guild."
  @spec get_state(Api.id(), Api.id()) :: Api.result(map())
  def get_state(guild_id, user_id) do
    Client.request(:get, "/guilds/#{guild_id}/voice-states/#{user_id}")
  end

  @doc "Edits the bot's voice state, e.g. to request to speak on a stage."
  @spec update_current_state(Api.id(), Api.params()) :: Api.result()
  def update_current_state(guild_id, params) do
    Client.request(:patch, "/guilds/#{guild_id}/voice-states/@me", json: params)
  end

  @doc "Edits a user's voice state on a stage."
  @spec update_state(Api.id(), Api.id(), Api.params()) :: Api.result()
  def update_state(guild_id, user_id, params) do
    Client.request(:patch, "/guilds/#{guild_id}/voice-states/#{user_id}", json: params)
  end
end
