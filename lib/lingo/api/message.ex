defmodule Lingo.Api.Message do
  @moduledoc """
  Messages: sending, forwarding, editing, deleting, bulk deletion and search.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Api.Message.Search
  alias Lingo.Rest.{Body, Client}
  alias Lingo.Type.Message

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

  @typedoc """
  A page of search results. `messages` nests each match in a list of its
  own, as Discord sends them; `threads` are the threads they're in, and
  `members` the bot's membership in those it has joined.
  """
  @type search_result :: %{
          doing_deep_historical_index: boolean(),
          documents_indexed: non_neg_integer() | nil,
          total_results: non_neg_integer(),
          messages: [[Message.t()]],
          threads: [Lingo.Type.Channel.t()],
          members: [Lingo.Type.ThreadMember.t()]
        }

  @doc """
  Searches a guild's messages with Discord's search options (`content:`,
  `author_id:`, `channel_id:`, `has:`, `limit:`, `offset:`...); options that
  take several values take lists. Retries while Discord is still indexing
  the guild: `:search_index_retries` times (3), waiting what Discord asks or
  `:search_index_short_delay` ms (1000).
  """
  @spec search(Api.id(), keyword()) :: Api.result(search_result())
  def search(guild_id, opts \\ []), do: Search.run(guild_id, opts)
end
