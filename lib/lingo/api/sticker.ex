defmodule Lingo.Api.Sticker do
  @moduledoc """
  Stickers and sticker packs.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.{Sticker, StickerPack}

  @doc "Fetches a sticker."
  @spec get(Api.id()) :: Api.result(Sticker.t())
  def get(sticker_id) do
    Client.request(:get, "/stickers/#{sticker_id}") |> Client.into(&Sticker.new/1)
  end

  @doc "Lists Discord's sticker packs."
  @spec list_packs() :: Api.result([StickerPack.t()])
  def list_packs do
    Client.request(:get, "/sticker-packs")
    |> Client.into(&Enum.map(&1["sticker_packs"] || [], fn pack -> StickerPack.new(pack) end))
  end

  @doc "Fetches a sticker pack."
  @spec get_pack(Api.id()) :: Api.result(StickerPack.t())
  def get_pack(pack_id) do
    Client.request(:get, "/sticker-packs/#{pack_id}") |> Client.into(&StickerPack.new/1)
  end

  @doc "Lists a guild's stickers."
  @spec list_guild(Api.id()) :: Api.result([Sticker.t()])
  def list_guild(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/stickers") |> Client.into(&Sticker.new/1)
  end

  @doc "Fetches a guild sticker."
  @spec get_guild(Api.id(), Api.id()) :: Api.result(Sticker.t())
  def get_guild(guild_id, sticker_id) do
    Client.request(:get, "/guilds/#{guild_id}/stickers/#{sticker_id}")
    |> Client.into(&Sticker.new/1)
  end

  @doc "Creates a guild sticker."
  @spec create_guild(Api.id(), Api.params(), keyword()) :: Api.result(Sticker.t())
  def create_guild(guild_id, params, opts \\ []) do
    multipart = [
      {"name", params[:name] || params["name"]},
      {"description", params[:description] || params["description"]},
      {"tags", params[:tags] || params["tags"]},
      {"file", params[:file] || params["file"]}
    ]

    Client.request(:post, "/guilds/#{guild_id}/stickers",
      multipart: multipart,
      reason: opts[:reason]
    )
    |> Client.into(&Sticker.new/1)
  end

  @doc "Edits a guild sticker."
  @spec update_guild(Api.id(), Api.id(), Api.params(), keyword()) :: Api.result(Sticker.t())
  def update_guild(guild_id, sticker_id, params, opts \\ []) do
    Client.request(:patch, "/guilds/#{guild_id}/stickers/#{sticker_id}",
      json: params,
      reason: opts[:reason]
    )
    |> Client.into(&Sticker.new/1)
  end

  @doc "Deletes a guild sticker."
  @spec delete_guild(Api.id(), Api.id(), keyword()) :: Api.result()
  def delete_guild(guild_id, sticker_id, opts \\ []) do
    Client.request(:delete, "/guilds/#{guild_id}/stickers/#{sticker_id}", reason: opts[:reason])
  end
end
