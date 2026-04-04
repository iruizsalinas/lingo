defmodule Lingo.Api.Message do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.Message

  def get(channel_id, message_id) do
    with {:ok, data} <- Client.request(:get, "/channels/#{channel_id}/messages/#{message_id}") do
      {:ok, Message.new(data)}
    end
  end

  def list(channel_id, opts \\ []) do
    params =
      opts
      |> Keyword.take([:around, :before, :after, :limit])
      |> Enum.into(%{})

    with {:ok, data} <- Client.request(:get, "/channels/#{channel_id}/messages", params: params) do
      {:ok, Enum.map(data, &Message.new/1)}
    end
  end

  def create(channel_id, params) when is_map(params) do
    {files, json} = Map.pop(params, :files)

    if files do
      multipart = build_multipart(json, files)
      do_create(channel_id, multipart: multipart)
    else
      do_create(channel_id, json: json)
    end
  end

  def create(channel_id, params) when is_list(params) do
    create(channel_id, Map.new(params))
  end

  def create(channel_id, content) when is_binary(content) do
    create(channel_id, %{content: content})
  end

  defp do_create(channel_id, opts) do
    with {:ok, data} <- Client.request(:post, "/channels/#{channel_id}/messages", opts) do
      {:ok, Message.new(data)}
    end
  end

  def edit(channel_id, message_id, params) when is_map(params) do
    {files, json} = Map.pop(params, :files)

    opts =
      if files do
        [multipart: build_multipart(json, files)]
      else
        [json: json]
      end

    with {:ok, data} <-
           Client.request(:patch, "/channels/#{channel_id}/messages/#{message_id}", opts) do
      {:ok, Message.new(data)}
    end
  end

  def edit(channel_id, message_id, params) when is_list(params) do
    edit(channel_id, message_id, Map.new(params))
  end

  def delete(channel_id, message_id, opts \\ []) do
    Client.request(:delete, "/channels/#{channel_id}/messages/#{message_id}",
      reason: opts[:reason]
    )
  end

  def bulk_delete(channel_id, message_ids, opts \\ []) when is_list(message_ids) do
    message_ids
    |> Enum.chunk_every(100)
    |> Enum.reduce_while(:ok, fn chunk, _acc ->
      result =
        if length(chunk) == 1 do
          delete(channel_id, hd(chunk), opts)
        else
          Client.request(:post, "/channels/#{channel_id}/messages/bulk-delete",
            json: %{messages: chunk},
            reason: opts[:reason]
          )
        end

      case result do
        :ok -> {:cont, :ok}
        {:ok, _} -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  def crosspost(channel_id, message_id) do
    with {:ok, data} <-
           Client.request(:post, "/channels/#{channel_id}/messages/#{message_id}/crosspost") do
      {:ok, Message.new(data)}
    end
  end

  def search(guild_id, opts \\ []) do
    params =
      opts
      |> Keyword.take([
        :content,
        :author_id,
        :mentions,
        :has,
        :min_id,
        :max_id,
        :channel_id,
        :pinned,
        :limit,
        :offset,
        :sort_by,
        :sort_order
      ])
      |> Enum.into(%{})

    Client.request(:get, "/guilds/#{guild_id}/messages/search", params: params)
  end

  defp build_multipart(json, files), do: Client.build_multipart(json, files)
end
