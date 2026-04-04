defmodule Lingo.Api.Command do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.ApplicationCommand

  def list_global(application_id) do
    with {:ok, data} <- Client.request(:get, "/applications/#{application_id}/commands") do
      {:ok, Enum.map(data, &ApplicationCommand.new/1)}
    end
  end

  def get_global(application_id, command_id) do
    with {:ok, data} <-
           Client.request(:get, "/applications/#{application_id}/commands/#{command_id}") do
      {:ok, ApplicationCommand.new(data)}
    end
  end

  def create_global(application_id, params) do
    with {:ok, data} <-
           Client.request(:post, "/applications/#{application_id}/commands", json: params) do
      {:ok, ApplicationCommand.new(data)}
    end
  end

  def edit_global(application_id, command_id, params) do
    with {:ok, data} <-
           Client.request(:patch, "/applications/#{application_id}/commands/#{command_id}",
             json: params
           ) do
      {:ok, ApplicationCommand.new(data)}
    end
  end

  def delete_global(application_id, command_id) do
    Client.request(:delete, "/applications/#{application_id}/commands/#{command_id}")
  end

  def bulk_overwrite_global(application_id, commands) do
    with {:ok, data} <-
           Client.request(:put, "/applications/#{application_id}/commands", json: commands) do
      {:ok, Enum.map(data, &ApplicationCommand.new/1)}
    end
  end

  # guild-scoped

  def list_guild(application_id, guild_id) do
    with {:ok, data} <-
           Client.request(:get, "/applications/#{application_id}/guilds/#{guild_id}/commands") do
      {:ok, Enum.map(data, &ApplicationCommand.new/1)}
    end
  end

  def get_guild(application_id, guild_id, command_id) do
    with {:ok, data} <-
           Client.request(
             :get,
             "/applications/#{application_id}/guilds/#{guild_id}/commands/#{command_id}"
           ) do
      {:ok, ApplicationCommand.new(data)}
    end
  end

  def create_guild(application_id, guild_id, params) do
    with {:ok, data} <-
           Client.request(:post, "/applications/#{application_id}/guilds/#{guild_id}/commands",
             json: params
           ) do
      {:ok, ApplicationCommand.new(data)}
    end
  end

  def edit_guild(application_id, guild_id, command_id, params) do
    with {:ok, data} <-
           Client.request(
             :patch,
             "/applications/#{application_id}/guilds/#{guild_id}/commands/#{command_id}",
             json: params
           ) do
      {:ok, ApplicationCommand.new(data)}
    end
  end

  def delete_guild(application_id, guild_id, command_id) do
    Client.request(
      :delete,
      "/applications/#{application_id}/guilds/#{guild_id}/commands/#{command_id}"
    )
  end

  def bulk_overwrite_guild(application_id, guild_id, commands) do
    with {:ok, data} <-
           Client.request(:put, "/applications/#{application_id}/guilds/#{guild_id}/commands",
             json: commands
           ) do
      {:ok, Enum.map(data, &ApplicationCommand.new/1)}
    end
  end

  def get_all_permissions(application_id, guild_id) do
    Client.request(
      :get,
      "/applications/#{application_id}/guilds/#{guild_id}/commands/permissions"
    )
  end

  def get_permissions(application_id, guild_id, command_id) do
    Client.request(
      :get,
      "/applications/#{application_id}/guilds/#{guild_id}/commands/#{command_id}/permissions"
    )
  end
end
