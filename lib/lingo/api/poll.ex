defmodule Lingo.Api.Poll do
  @moduledoc false

  alias Lingo.Api.Client

  def get_answer_voters(channel_id, message_id, answer_id, opts \\ []) do
    params =
      opts
      |> Keyword.take([:after, :limit])
      |> Enum.into(%{})

    Client.request(
      :get,
      "/channels/#{channel_id}/polls/#{message_id}/answers/#{answer_id}",
      params: params
    )
  end

  def expire(channel_id, message_id) do
    Client.request(:post, "/channels/#{channel_id}/polls/#{message_id}/expire")
  end
end
