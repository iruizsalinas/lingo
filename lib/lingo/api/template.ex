defmodule Lingo.Api.Template do
  @moduledoc """
  Guild templates.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.GuildTemplate

  @doc "Fetches a guild template by code."
  @spec get(String.t()) :: Api.result(GuildTemplate.t())
  def get(template_code) do
    Client.request(:get, "/guilds/templates/#{template_code}")
    |> Client.into(&GuildTemplate.new/1)
  end

  @doc "Lists a guild's templates."
  @spec list(Api.id()) :: Api.result([GuildTemplate.t()])
  def list(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/templates") |> Client.into(&GuildTemplate.new/1)
  end

  @doc "Creates a template from a guild."
  @spec create(Api.id(), Api.params()) :: Api.result(GuildTemplate.t())
  def create(guild_id, params) do
    Client.request(:post, "/guilds/#{guild_id}/templates", json: params)
    |> Client.into(&GuildTemplate.new/1)
  end

  @doc "Updates a template to the guild's current state."
  @spec sync(Api.id(), String.t()) :: Api.result(GuildTemplate.t())
  def sync(guild_id, template_code) do
    Client.request(:put, "/guilds/#{guild_id}/templates/#{template_code}")
    |> Client.into(&GuildTemplate.new/1)
  end

  @doc "Edits a guild template."
  @spec update(Api.id(), String.t(), Api.params()) :: Api.result(GuildTemplate.t())
  def update(guild_id, template_code, params) do
    Client.request(:patch, "/guilds/#{guild_id}/templates/#{template_code}", json: params)
    |> Client.into(&GuildTemplate.new/1)
  end

  @doc "Deletes a guild template."
  @spec delete(Api.id(), String.t()) :: Api.result(map())
  def delete(guild_id, template_code) do
    Client.request(:delete, "/guilds/#{guild_id}/templates/#{template_code}")
  end
end
