defmodule Lingo.Api.Poll do
  @moduledoc """
  Polls.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client

  @doc "Lists the users who voted for a poll answer."
  @spec list_answer_voters(Api.id(), Api.id(), Api.id(), keyword()) :: Api.result(map())
  def list_answer_voters(channel_id, message_id, answer_id, opts \\ []) do
    params =
      Client.params(opts)

    Client.request(
      :get,
      "/channels/#{channel_id}/polls/#{message_id}/answers/#{answer_id}",
      params: params
    )
  end

  @doc "Ends a poll early."
  @spec expire(Api.id(), Api.id()) :: Api.result(map())
  def expire(channel_id, message_id) do
    Client.request(:post, "/channels/#{channel_id}/polls/#{message_id}/expire")
  end
end
