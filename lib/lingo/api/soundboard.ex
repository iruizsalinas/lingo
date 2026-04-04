defmodule Lingo.Api.Soundboard do
  @moduledoc false

  alias Lingo.Api.Client

  def send_sound(channel_id, params) do
    Client.request(:post, "/channels/#{channel_id}/send-soundboard-sound", json: params)
  end

  def list_defaults do
    Client.request(:get, "/soundboard-default-sounds")
  end

  def list_guild(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/soundboard-sounds")
  end

  def get_guild(guild_id, sound_id) do
    Client.request(:get, "/guilds/#{guild_id}/soundboard-sounds/#{sound_id}")
  end

  def create_guild(guild_id, params, opts \\ []) do
    Client.request(:post, "/guilds/#{guild_id}/soundboard-sounds",
      json: params,
      reason: opts[:reason]
    )
  end

  def modify_guild(guild_id, sound_id, params, opts \\ []) do
    Client.request(:patch, "/guilds/#{guild_id}/soundboard-sounds/#{sound_id}",
      json: params,
      reason: opts[:reason]
    )
  end

  def delete_guild(guild_id, sound_id, opts \\ []) do
    Client.request(:delete, "/guilds/#{guild_id}/soundboard-sounds/#{sound_id}",
      reason: opts[:reason]
    )
  end
end
