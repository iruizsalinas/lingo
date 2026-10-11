defmodule Lingo.Api.Poll do
  @moduledoc """
  Polls.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.{Message, User}

  @doc """
  Lists the users who voted for a poll answer, by its `answer_id`. Options:
  `:after` (a user id) and `:limit`.
  """
  @spec list_answer_voters(Api.id(), Api.id(), integer() | String.t(), keyword()) ::
          Api.result([User.t()])
  def list_answer_voters(channel_id, message_id, answer_id, opts \\ []) do
    Client.request(
      :get,
      "/channels/#{channel_id}/polls/#{message_id}/answers/#{answer_id}",
      params: Client.params(opts)
    )
    |> Client.into(&Enum.map(&1["users"] || [], fn user -> User.new(user) end))
  end

  @doc "Ends a poll early, returning its message."
  @spec expire(Api.id(), Api.id()) :: Api.result(Message.t())
  def expire(channel_id, message_id) do
    Client.request(:post, "/channels/#{channel_id}/polls/#{message_id}/expire")
    |> Client.into(&Message.new/1)
  end
end
