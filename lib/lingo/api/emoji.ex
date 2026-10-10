defmodule Lingo.Api.Emoji do
  @moduledoc """
  Guild emojis and the application's own emojis.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.Emoji

  @doc "Lists a guild's emojis."
  @spec list(Api.id()) :: Api.result([Emoji.t()])
  def list(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/emojis") |> Client.into(&Emoji.new/1)
  end

  @doc "Fetches a guild emoji."
  @spec get(Api.id(), Api.id()) :: Api.result(Emoji.t())
  def get(guild_id, emoji_id) do
    Client.request(:get, "/guilds/#{guild_id}/emojis/#{emoji_id}") |> Client.into(&Emoji.new/1)
  end

  @doc "Creates a guild emoji from a data URI image."
  @spec create(Api.id(), Api.params(), keyword()) :: Api.result(Emoji.t())
  def create(guild_id, params, opts \\ []) do
    Client.request(:post, "/guilds/#{guild_id}/emojis",
      json: params,
      reason: opts[:reason]
    )
    |> Client.into(&Emoji.new/1)
  end

  @doc "Edits a guild emoji."
  @spec update(Api.id(), Api.id(), Api.params(), keyword()) :: Api.result(Emoji.t())
  def update(guild_id, emoji_id, params, opts \\ []) do
    Client.request(:patch, "/guilds/#{guild_id}/emojis/#{emoji_id}",
      json: params,
      reason: opts[:reason]
    )
    |> Client.into(&Emoji.new/1)
  end

  @doc "Deletes a guild emoji."
  @spec delete(Api.id(), Api.id(), keyword()) :: Api.result()
  def delete(guild_id, emoji_id, opts \\ []) do
    Client.request(:delete, "/guilds/#{guild_id}/emojis/#{emoji_id}", reason: opts[:reason])
  end

  # app emojis

  @doc "Lists the application's emojis."
  @spec list_application() :: Api.result([Emoji.t()])
  def list_application do
    with {:ok, application_id} <- Lingo.Instance.application_id(),
         {:ok, data} <- Client.request(:get, "/applications/#{application_id}/emojis") do
      {:ok, Enum.map(data["items"] || data, &Emoji.new/1)}
    end
  end

  @doc "Fetches an application emoji."
  @spec get_application(Api.id()) :: Api.result(Emoji.t())
  def get_application(emoji_id) do
    Client.app(fn application_id ->
      Client.request(:get, "/applications/#{application_id}/emojis/#{emoji_id}")
      |> Client.into(&Emoji.new/1)
    end)
  end

  @doc "Creates an application emoji."
  @spec create_application(Api.params()) :: Api.result(Emoji.t())
  def create_application(params) do
    Client.app(fn application_id ->
      Client.request(:post, "/applications/#{application_id}/emojis", json: params)
      |> Client.into(&Emoji.new/1)
    end)
  end

  @doc "Renames an application emoji."
  @spec update_application(Api.id(), Api.params()) :: Api.result(Emoji.t())
  def update_application(emoji_id, params) do
    Client.app(fn application_id ->
      Client.request(:patch, "/applications/#{application_id}/emojis/#{emoji_id}", json: params)
      |> Client.into(&Emoji.new/1)
    end)
  end

  @doc "Deletes an application emoji."
  @spec delete_application(Api.id()) :: Api.result()
  def delete_application(emoji_id) do
    Client.app(fn application_id ->
      Client.request(:delete, "/applications/#{application_id}/emojis/#{emoji_id}")
    end)
  end
end
