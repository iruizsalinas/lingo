defmodule Lingo.Api.Reaction do
  @moduledoc """
  Message reactions. Emojis are unicode characters or `name:id` for custom ones.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.User

  @custom_emoji_markdown ~r/^<a?:([A-Za-z0-9_]{2,32}):(\d+)>$/

  @doc "Reacts to a message, with a unicode emoji or `name:id` for a custom one."
  @spec create(Api.id(), Api.id(), String.t() | Lingo.Type.Emoji.t()) :: Api.result()
  def create(channel_id, message_id, emoji) do
    Client.request(
      :put,
      "/channels/#{channel_id}/messages/#{message_id}/reactions/#{encode_emoji(emoji)}/@me"
    )
  end

  @doc "Removes the bot's reaction."
  @spec delete_own(Api.id(), Api.id(), String.t() | Lingo.Type.Emoji.t()) :: Api.result()
  def delete_own(channel_id, message_id, emoji) do
    Client.request(
      :delete,
      "/channels/#{channel_id}/messages/#{message_id}/reactions/#{encode_emoji(emoji)}/@me"
    )
  end

  @doc "Removes another user's reaction."
  @spec delete_user(Api.id(), Api.id(), String.t() | Lingo.Type.Emoji.t(), Api.id()) ::
          Api.result()
  def delete_user(channel_id, message_id, emoji, user_id) do
    Client.request(
      :delete,
      "/channels/#{channel_id}/messages/#{message_id}/reactions/#{encode_emoji(emoji)}/#{user_id}"
    )
  end

  @doc "Lists the users who reacted with an emoji."
  @spec list_users(Api.id(), Api.id(), String.t() | Lingo.Type.Emoji.t(), keyword()) ::
          Api.result([User.t()])
  def list_users(channel_id, message_id, emoji, opts \\ []) do
    params =
      Client.params(opts)

    Client.request(
      :get,
      "/channels/#{channel_id}/messages/#{message_id}/reactions/#{encode_emoji(emoji)}",
      params: params
    )
    |> Client.into(&User.new/1)
  end

  @doc "Removes every reaction from a message."
  @spec delete_all(Api.id(), Api.id()) :: Api.result()
  def delete_all(channel_id, message_id) do
    Client.request(:delete, "/channels/#{channel_id}/messages/#{message_id}/reactions")
  end

  @doc "Removes every reaction with one emoji from a message."
  @spec delete_all_for_emoji(Api.id(), Api.id(), String.t() | Lingo.Type.Emoji.t()) ::
          Api.result()
  def delete_all_for_emoji(channel_id, message_id, emoji) do
    Client.request(
      :delete,
      "/channels/#{channel_id}/messages/#{message_id}/reactions/#{encode_emoji(emoji)}"
    )
  end

  @doc false
  @spec encode_emoji(String.t() | Lingo.Type.Emoji.t()) :: String.t()
  def encode_emoji(emoji) when is_binary(emoji) do
    emoji
    |> normalize_custom_emoji_markdown()
    |> URI.encode(&reaction_path_char?/1)
  end

  def encode_emoji(%{id: nil, name: name}), do: encode_emoji(name)
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
