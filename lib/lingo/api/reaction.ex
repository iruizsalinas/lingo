defmodule Lingo.Api.Reaction do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.User

  def create(channel_id, message_id, emoji) do
    Client.request(
      :put,
      "/channels/#{channel_id}/messages/#{message_id}/reactions/#{encode_emoji(emoji)}/@me"
    )
  end

  def delete_own(channel_id, message_id, emoji) do
    Client.request(
      :delete,
      "/channels/#{channel_id}/messages/#{message_id}/reactions/#{encode_emoji(emoji)}/@me"
    )
  end

  def delete_user(channel_id, message_id, emoji, user_id) do
    Client.request(
      :delete,
      "/channels/#{channel_id}/messages/#{message_id}/reactions/#{encode_emoji(emoji)}/#{user_id}"
    )
  end

  def get_users(channel_id, message_id, emoji, opts \\ []) do
    params =
      opts
      |> Keyword.take([:after, :limit, :type])
      |> Enum.into(%{})

    with {:ok, data} <-
           Client.request(
             :get,
             "/channels/#{channel_id}/messages/#{message_id}/reactions/#{encode_emoji(emoji)}",
             params: params
           ) do
      {:ok, Enum.map(data, &User.new/1)}
    end
  end

  def delete_all(channel_id, message_id) do
    Client.request(:delete, "/channels/#{channel_id}/messages/#{message_id}/reactions")
  end

  def delete_all_for_emoji(channel_id, message_id, emoji) do
    Client.request(
      :delete,
      "/channels/#{channel_id}/messages/#{message_id}/reactions/#{encode_emoji(emoji)}"
    )
  end

  defp encode_emoji(emoji) when is_binary(emoji), do: URI.encode(emoji)
  defp encode_emoji(%{id: id, name: name}), do: "#{name}:#{id}"
end
