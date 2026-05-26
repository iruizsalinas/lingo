defmodule Lingo.Api.Message do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.Message

  @search_index_retries 3
  @search_index_short_delay 1_000
  @search_array_params ~w(
    channel_id
    author_type
    author_id
    mentions
    mentions_role_id
    replied_to_user_id
    replied_to_message_id
    has
    embed_type
    embed_provider
    link_hostname
    attachment_filename
    attachment_extension
  )a

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
    search_index_retries = Keyword.get(opts, :search_index_retries, @search_index_retries)

    search_index_short_delay =
      Keyword.get(opts, :search_index_short_delay, @search_index_short_delay)

    params =
      opts
      |> Keyword.take([
        :content,
        :author_id,
        :author_type,
        :mentions,
        :mentions_role_id,
        :mention_everyone,
        :replied_to_user_id,
        :replied_to_message_id,
        :has,
        :slop,
        :min_id,
        :max_id,
        :channel_id,
        :pinned,
        :embed_type,
        :embed_provider,
        :link_hostname,
        :attachment_filename,
        :attachment_extension,
        :limit,
        :offset,
        :sort_by,
        :sort_order,
        :include_nsfw
      ])
      |> normalize_search_params()

    do_search(guild_id, params, search_index_retries, search_index_short_delay)
  end

  defp do_search(guild_id, params, retries_left, short_delay) do
    case Client.request(:get, "/guilds/#{guild_id}/messages/search", params: params) do
      {:ok, %{"code" => 110_000} = body} when retries_left > 0 ->
        Process.sleep(search_index_retry_after(body, short_delay))
        do_search(guild_id, params, retries_left - 1, short_delay)

      {:ok, %{"code" => 110_000} = body} ->
        {:error, {:index_not_ready, body}}

      result ->
        result
    end
  end

  defp search_index_retry_after(%{"retry_after" => seconds}, short_delay)
       when is_number(seconds) do
    ms = trunc(seconds * 1000)
    if ms > 0, do: ms, else: short_delay
  end

  defp search_index_retry_after(_body, short_delay), do: short_delay

  defp normalize_search_params(params) do
    Enum.flat_map(params, fn
      {key, values} when key in @search_array_params and is_list(values) ->
        Enum.map(values, &{key, &1})

      param ->
        [param]
    end)
  end

  defp build_multipart(json, files), do: Client.build_multipart(json, files)
end
