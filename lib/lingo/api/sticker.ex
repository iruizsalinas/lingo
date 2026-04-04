defmodule Lingo.Api.Sticker do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.Sticker

  def get(sticker_id) do
    with {:ok, data} <- Client.request(:get, "/stickers/#{sticker_id}") do
      {:ok, Sticker.new(data)}
    end
  end

  def list_packs do
    Client.request(:get, "/sticker-packs")
  end

  def get_pack(pack_id) do
    Client.request(:get, "/sticker-packs/#{pack_id}")
  end

  def list_guild(guild_id) do
    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/stickers") do
      {:ok, Enum.map(data, &Sticker.new/1)}
    end
  end

  def get_guild(guild_id, sticker_id) do
    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/stickers/#{sticker_id}") do
      {:ok, Sticker.new(data)}
    end
  end

  def create_guild(guild_id, params, opts \\ []) do
    multipart = [
      {"name", params[:name] || params["name"]},
      {"description", params[:description] || params["description"]},
      {"tags", params[:tags] || params["tags"]},
      {"file", params[:file] || params["file"]}
    ]

    with {:ok, data} <-
           Client.request(:post, "/guilds/#{guild_id}/stickers",
             multipart: multipart,
             reason: opts[:reason]
           ) do
      {:ok, Sticker.new(data)}
    end
  end

  def modify_guild(guild_id, sticker_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:patch, "/guilds/#{guild_id}/stickers/#{sticker_id}",
             json: params,
             reason: opts[:reason]
           ) do
      {:ok, Sticker.new(data)}
    end
  end

  def delete_guild(guild_id, sticker_id, opts \\ []) do
    Client.request(:delete, "/guilds/#{guild_id}/stickers/#{sticker_id}", reason: opts[:reason])
  end
end
