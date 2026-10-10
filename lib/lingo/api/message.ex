defmodule Lingo.Api.Message do
  @moduledoc """
  Messages: sending, forwarding, editing, deleting, bulk deletion and search.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.{Body, Client}
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

  @doc "Fetches a message."
  @spec get(Api.id(), Api.id()) :: Api.result(Message.t())
  def get(channel_id, message_id) do
    Client.request(:get, "/channels/#{channel_id}/messages/#{message_id}")
    |> Client.into(&Message.new/1)
  end

  @doc "Lists a channel's messages, newest first. Takes `limit:`, `before:`, `after:` and `around:`."
  @spec list(Api.id(), keyword()) :: Api.result([Message.t()])
  def list(channel_id, opts \\ []) do
    params =
      Client.params(opts)

    Client.request(:get, "/channels/#{channel_id}/messages", params: params)
    |> Client.into(&Message.new/1)
  end

  @doc "Sends a message. Pass a string, or a map or keyword list of message fields, including `:files` as `{name, binary}` tuples."
  @spec create(Api.id(), Api.content()) :: Api.result(Message.t())
  def create(channel_id, content) do
    Client.request(:post, "/channels/#{channel_id}/messages", Body.opts(content))
    |> Client.into(&Message.new/1)
  end

  @doc """
  Edits a message the bot sent.

  `:attachments` lists every attachment to keep, by `:id`, and may change
  their `:description` or mark them `is_spoiler: true`; new `:files` are
  added to them.
  """
  @spec update(Api.id(), Api.id(), Api.content()) :: Api.result(Message.t())
  def update(channel_id, message_id, params) do
    Client.request(
      :patch,
      "/channels/#{channel_id}/messages/#{message_id}",
      Body.opts(params)
    )
    |> Client.into(&Message.new/1)
  end

  @doc "Deletes a message."
  @spec delete(Api.id(), Api.id(), keyword()) :: Api.result()
  def delete(channel_id, message_id, opts \\ []) do
    Client.request(:delete, "/channels/#{channel_id}/messages/#{message_id}",
      reason: opts[:reason]
    )
  end

  @doc "Deletes many messages at once, in chunks of 100. Messages older than two weeks can't be bulk deleted."
  @spec bulk_delete(Api.id(), [Api.id()], keyword()) :: Api.result()
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

  @doc "Publishes a message in an announcement channel to its followers."
  @spec crosspost(Api.id(), Api.id()) :: Api.result(Message.t())
  def crosspost(channel_id, message_id) do
    Client.request(:post, "/channels/#{channel_id}/messages/#{message_id}/crosspost")
    |> Client.into(&Message.new/1)
  end

  @doc """
  Forwards a message into `channel_id`. The bot must be able to read the
  message's content (Discord answers code 160014 otherwise).
  """
  @spec forward(Api.id(), Api.id(), Api.id()) :: Api.result(Message.t())
  def forward(channel_id, from_channel_id, message_id) do
    reference = %{type: 1, channel_id: from_channel_id, message_id: message_id}
    create(channel_id, %{message_reference: reference})
  end

  @doc "Searches a guild's messages. Retries while Discord is still indexing the guild."
  @spec search(Api.id(), keyword()) :: Api.result(map())
  def search(guild_id, opts \\ []) do
    search_index_retries = Keyword.get(opts, :search_index_retries, @search_index_retries)

    search_index_short_delay =
      Keyword.get(opts, :search_index_short_delay, @search_index_short_delay)

    params =
      opts
      |> Keyword.drop([:search_index_retries, :search_index_short_delay])
      |> normalize_search_params()

    do_search(guild_id, params, search_index_retries, search_index_short_delay)
  end

  defp do_search(guild_id, params, retries_left, short_delay) do
    case Client.request(:get, "/guilds/#{guild_id}/messages/search", params: params) do
      {:ok, %{"code" => 110_000} = body} when retries_left > 0 ->
        Process.sleep(search_index_retry_after(body, short_delay))
        do_search(guild_id, params, retries_left - 1, short_delay)

      {:ok, %{"code" => 110_000} = body} ->
        {:error, %Lingo.Error{reason: :index_not_ready, details: body}}

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
end
