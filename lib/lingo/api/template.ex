defmodule Lingo.Api.Template do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.GuildTemplate

  def get(template_code) do
    with {:ok, data} <- Client.request(:get, "/guilds/templates/#{template_code}") do
      {:ok, GuildTemplate.new(data)}
    end
  end

  def list(guild_id) do
    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/templates") do
      {:ok, Enum.map(data, &GuildTemplate.new/1)}
    end
  end

  def create(guild_id, params) do
    with {:ok, data} <- Client.request(:post, "/guilds/#{guild_id}/templates", json: params) do
      {:ok, GuildTemplate.new(data)}
    end
  end

  def sync(guild_id, template_code) do
    with {:ok, data} <- Client.request(:put, "/guilds/#{guild_id}/templates/#{template_code}") do
      {:ok, GuildTemplate.new(data)}
    end
  end

  def modify(guild_id, template_code, params) do
    with {:ok, data} <-
           Client.request(:patch, "/guilds/#{guild_id}/templates/#{template_code}", json: params) do
      {:ok, GuildTemplate.new(data)}
    end
  end

  def delete(guild_id, template_code) do
    Client.request(:delete, "/guilds/#{guild_id}/templates/#{template_code}")
  end
end
