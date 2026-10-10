defmodule Lingo.Api.Command do
  @moduledoc """
  Application commands, global and per guild. Bots usually declare commands with `Lingo.Bot.Commands` and register them with `Lingo.register_commands/1` instead.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.ApplicationCommand

  @doc "Lists the global application commands."
  @spec list_global() :: Api.result([ApplicationCommand.t()])
  def list_global do
    Client.app(fn application_id ->
      Client.request(:get, "/applications/#{application_id}/commands")
      |> Client.into(&ApplicationCommand.new/1)
    end)
  end

  @doc "Fetches a global application command."
  @spec get_global(Api.id()) :: Api.result(ApplicationCommand.t())
  def get_global(command_id) do
    Client.app(fn application_id ->
      Client.request(:get, "/applications/#{application_id}/commands/#{command_id}")
      |> Client.into(&ApplicationCommand.new/1)
    end)
  end

  @doc "Creates or replaces one global application command."
  @spec create_global(Api.params()) :: Api.result(ApplicationCommand.t())
  def create_global(params) do
    Client.app(fn application_id ->
      Client.request(:post, "/applications/#{application_id}/commands", json: params)
      |> Client.into(&ApplicationCommand.new/1)
    end)
  end

  @doc "Edits a global application command."
  @spec update_global(Api.id(), Api.params()) :: Api.result(ApplicationCommand.t())
  def update_global(command_id, params) do
    Client.app(fn application_id ->
      Client.request(:patch, "/applications/#{application_id}/commands/#{command_id}",
        json: params
      )
      |> Client.into(&ApplicationCommand.new/1)
    end)
  end

  @doc "Deletes a global application command."
  @spec delete_global(Api.id()) :: Api.result()
  def delete_global(command_id) do
    Client.app(fn application_id ->
      Client.request(:delete, "/applications/#{application_id}/commands/#{command_id}")
    end)
  end

  @doc "Replaces all global application commands with `commands`."
  @spec bulk_overwrite_global([map()]) :: Api.result([ApplicationCommand.t()])
  def bulk_overwrite_global(commands) do
    Client.app(fn application_id ->
      Client.request(:put, "/applications/#{application_id}/commands", json: commands)
      |> Client.into(&ApplicationCommand.new/1)
    end)
  end

  # guild-scoped

  @doc "Lists a guild's application commands."
  @spec list_guild(Api.id()) :: Api.result([ApplicationCommand.t()])
  def list_guild(guild_id) do
    Client.app(fn application_id ->
      Client.request(:get, "/applications/#{application_id}/guilds/#{guild_id}/commands")
      |> Client.into(&ApplicationCommand.new/1)
    end)
  end

  @doc "Fetches a guild application command."
  @spec get_guild(Api.id(), Api.id()) :: Api.result(ApplicationCommand.t())
  def get_guild(guild_id, command_id) do
    Client.app(fn application_id ->
      Client.request(
        :get,
        "/applications/#{application_id}/guilds/#{guild_id}/commands/#{command_id}"
      )
      |> Client.into(&ApplicationCommand.new/1)
    end)
  end

  @doc "Creates or replaces one guild application command."
  @spec create_guild(Api.id(), Api.params()) :: Api.result(ApplicationCommand.t())
  def create_guild(guild_id, params) do
    Client.app(fn application_id ->
      Client.request(:post, "/applications/#{application_id}/guilds/#{guild_id}/commands",
        json: params
      )
      |> Client.into(&ApplicationCommand.new/1)
    end)
  end

  @doc "Edits a guild application command."
  @spec update_guild(Api.id(), Api.id(), Api.params()) :: Api.result(ApplicationCommand.t())
  def update_guild(guild_id, command_id, params) do
    Client.app(fn application_id ->
      Client.request(
        :patch,
        "/applications/#{application_id}/guilds/#{guild_id}/commands/#{command_id}",
        json: params
      )
      |> Client.into(&ApplicationCommand.new/1)
    end)
  end

  @doc "Deletes a guild application command."
  @spec delete_guild(Api.id(), Api.id()) :: Api.result()
  def delete_guild(guild_id, command_id) do
    Client.app(fn application_id ->
      Client.request(
        :delete,
        "/applications/#{application_id}/guilds/#{guild_id}/commands/#{command_id}"
      )
    end)
  end

  @doc "Replaces all of a guild's application commands with `commands`."
  @spec bulk_overwrite_guild(Api.id(), [map()]) :: Api.result([ApplicationCommand.t()])
  def bulk_overwrite_guild(guild_id, commands) do
    Client.app(fn application_id ->
      Client.request(:put, "/applications/#{application_id}/guilds/#{guild_id}/commands",
        json: commands
      )
      |> Client.into(&ApplicationCommand.new/1)
    end)
  end

  @doc "Lists the permission settings of every command in a guild."
  @spec list_permissions(Api.id()) :: Api.result([map()])
  def list_permissions(guild_id) do
    Client.app(fn application_id ->
      Client.request(
        :get,
        "/applications/#{application_id}/guilds/#{guild_id}/commands/permissions"
      )
    end)
  end

  @doc "Fetches the permission settings of one command in a guild."
  @spec get_permissions(Api.id(), Api.id()) :: Api.result(map())
  def get_permissions(guild_id, command_id) do
    Client.app(fn application_id ->
      Client.request(
        :get,
        "/applications/#{application_id}/guilds/#{guild_id}/commands/#{command_id}/permissions"
      )
    end)
  end
end
