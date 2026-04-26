defmodule Lingo.Api.Reaction do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.User

  @custom_emoji_markdown ~r/^<a?:([A-Za-z0-9_]{2,32}):(\d+)>$/

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

  @doc false
  def encode_emoji(emoji) when is_binary(emoji) do
    emoji
    |> normalize_custom_emoji_markdown()
    |> URI.encode(&reaction_path_char?/1)
  end

  def encode_emoji(%{id: id, name: name}), do: encode_emoji("#{name}:#{id}")

  defp normalize_custom_emoji_markdown(emoji) do
    case Regex.run(@custom_emoji_markdown, emoji) do
      [_, name, id] -> "#{name}:#{id}"
      _ -> emoji
    end
  end

  defp reaction_path_char?(?:), do: true
  defp reaction_path_char?(char), do: URI.char_unreserved?(char)
end
