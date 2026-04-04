defmodule Lingo.Api.Voice do
  @moduledoc false

  alias Lingo.Api.Client

  def list_regions do
    Client.request(:get, "/voice/regions")
  end

  def get_current_user_voice_state(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/voice-states/@me")
  end

  def get_user_voice_state(guild_id, user_id) do
    Client.request(:get, "/guilds/#{guild_id}/voice-states/#{user_id}")
  end

  def modify_current_user_voice_state(guild_id, params) do
    Client.request(:patch, "/guilds/#{guild_id}/voice-states/@me", json: params)
  end

  def modify_user_voice_state(guild_id, user_id, params) do
    Client.request(:patch, "/guilds/#{guild_id}/voice-states/#{user_id}", json: params)
  end
end
