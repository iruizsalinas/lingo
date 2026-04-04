defmodule Lingo.Api.Emoji do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.Emoji

  def list(guild_id) do
    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/emojis") do
      {:ok, Enum.map(data, &Emoji.new/1)}
    end
  end

  def get(guild_id, emoji_id) do
    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/emojis/#{emoji_id}") do
      {:ok, Emoji.new(data)}
    end
  end

  def create(guild_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:post, "/guilds/#{guild_id}/emojis",
             json: params,
             reason: opts[:reason]
           ) do
      {:ok, Emoji.new(data)}
    end
  end

  def modify(guild_id, emoji_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:patch, "/guilds/#{guild_id}/emojis/#{emoji_id}",
             json: params,
             reason: opts[:reason]
           ) do
      {:ok, Emoji.new(data)}
    end
  end

  def delete(guild_id, emoji_id, opts \\ []) do
    Client.request(:delete, "/guilds/#{guild_id}/emojis/#{emoji_id}", reason: opts[:reason])
  end

  # app emojis

  def list_application(application_id) do
    with {:ok, data} <- Client.request(:get, "/applications/#{application_id}/emojis") do
      {:ok, Enum.map(data["items"] || data, &Emoji.new/1)}
    end
  end

  def get_application(application_id, emoji_id) do
    with {:ok, data} <- Client.request(:get, "/applications/#{application_id}/emojis/#{emoji_id}") do
      {:ok, Emoji.new(data)}
    end
  end

  def create_application(application_id, params) do
    with {:ok, data} <-
           Client.request(:post, "/applications/#{application_id}/emojis", json: params) do
      {:ok, Emoji.new(data)}
    end
  end

  def modify_application(application_id, emoji_id, params) do
    with {:ok, data} <-
           Client.request(:patch, "/applications/#{application_id}/emojis/#{emoji_id}",
             json: params
           ) do
      {:ok, Emoji.new(data)}
    end
  end

  def delete_application(application_id, emoji_id) do
    Client.request(:delete, "/applications/#{application_id}/emojis/#{emoji_id}")
  end
end
