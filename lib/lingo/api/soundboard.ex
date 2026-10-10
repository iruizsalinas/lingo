defmodule Lingo.Api.Soundboard do
  @moduledoc """
  Soundboard sounds.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client

  @doc "Plays a soundboard sound in the voice channel the bot is in."
  @spec send_sound(Api.id(), Api.params()) :: Api.result()
  def send_sound(channel_id, params) do
    Client.request(:post, "/channels/#{channel_id}/send-soundboard-sound", json: params)
  end

  @doc "Lists Discord's default soundboard sounds."
  @spec list_defaults() :: Api.result([map()])
  def list_defaults do
    Client.request(:get, "/soundboard-default-sounds")
  end

  @doc "Lists a guild's soundboard sounds."
  @spec list_guild(Api.id()) :: Api.result(map())
  def list_guild(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/soundboard-sounds")
  end

  @doc "Fetches a guild soundboard sound."
  @spec get_guild(Api.id(), Api.id()) :: Api.result(map())
  def get_guild(guild_id, sound_id) do
    Client.request(:get, "/guilds/#{guild_id}/soundboard-sounds/#{sound_id}")
  end

  @doc "Creates a guild soundboard sound."
  @spec create_guild(Api.id(), Api.params(), keyword()) :: Api.result(map())
  def create_guild(guild_id, params, opts \\ []) do
    Client.request(:post, "/guilds/#{guild_id}/soundboard-sounds",
      json: params,
      reason: opts[:reason]
    )
  end

  @doc "Edits a guild soundboard sound."
  @spec update_guild(Api.id(), Api.id(), Api.params(), keyword()) :: Api.result(map())
  def update_guild(guild_id, sound_id, params, opts \\ []) do
    Client.request(:patch, "/guilds/#{guild_id}/soundboard-sounds/#{sound_id}",
      json: params,
      reason: opts[:reason]
    )
  end

  @doc "Deletes a guild soundboard sound."
  @spec delete_guild(Api.id(), Api.id(), keyword()) :: Api.result()
  def delete_guild(guild_id, sound_id, opts \\ []) do
    Client.request(:delete, "/guilds/#{guild_id}/soundboard-sounds/#{sound_id}",
      reason: opts[:reason]
    )
  end
end
