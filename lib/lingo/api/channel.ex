defmodule Lingo.Api.Channel do
  @moduledoc """
  Channels: settings, permission overwrites, pins, invites and typing.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.{Channel, Message}

  @doc "Fetches a channel or thread."
  @spec get(Api.id()) :: Api.result(Channel.t())
  def get(channel_id) do
    Client.request(:get, "/channels/#{channel_id}") |> Client.into(&Channel.new/1)
  end

  @doc "Edits a channel or thread."
  @spec update(Api.id(), Api.params(), keyword()) :: Api.result(Channel.t())
  def update(channel_id, params, opts \\ []) do
    Client.request(:patch, "/channels/#{channel_id}", json: params, reason: opts[:reason])
    |> Client.into(&Channel.new/1)
  end

  @doc "Deletes a channel, or closes a DM."
  @spec delete(Api.id(), keyword()) :: Api.result(Channel.t())
  def delete(channel_id, opts \\ []) do
    Client.request(:delete, "/channels/#{channel_id}", reason: opts[:reason])
    |> Client.into(&Channel.new/1)
  end

  @doc "Sets a permission overwrite for a role or member in a channel."
  @spec update_permission(Api.id(), Api.id(), Api.params(), keyword()) :: Api.result()
  def update_permission(channel_id, overwrite_id, params, opts \\ []) do
    Client.request(:put, "/channels/#{channel_id}/permissions/#{overwrite_id}",
      json: params,
      reason: opts[:reason]
    )
  end

  @doc "Removes a permission overwrite from a channel."
  @spec delete_permission(Api.id(), Api.id(), keyword()) :: Api.result()
  def delete_permission(channel_id, overwrite_id, opts \\ []) do
    Client.request(:delete, "/channels/#{channel_id}/permissions/#{overwrite_id}",
      reason: opts[:reason]
    )
  end

  @doc "Follows an announcement channel into another channel."
  @spec follow_announcement(Api.id(), Api.id(), keyword()) :: Api.result(map())
  def follow_announcement(channel_id, webhook_channel_id, opts \\ []) do
    Client.request(:post, "/channels/#{channel_id}/followers",
      json: %{webhook_channel_id: webhook_channel_id},
      reason: opts[:reason]
    )
  end

  @doc "Shows the bot as typing in a channel for a few seconds."
  @spec trigger_typing(Api.id()) :: Api.result()
  def trigger_typing(channel_id) do
    Client.request(:post, "/channels/#{channel_id}/typing")
  end

  @doc "Sets the status text of a voice channel."
  @spec set_voice_status(Api.id(), Api.params(), keyword()) :: Api.result()
  def set_voice_status(channel_id, params, opts \\ []) do
    Client.request(:put, "/channels/#{channel_id}/voice-status",
      json: params,
      reason: opts[:reason]
    )
  end

  @doc "Lists a channel's pinned messages."
  @spec list_pins(Api.id(), keyword()) ::
          Api.result(%{
            items: [%{pinned_at: String.t(), message: Message.t()}],
            has_more: boolean()
          })
  def list_pins(channel_id, opts \\ []) do
    params =
      Client.params(opts)

    with {:ok, data} <-
           Client.request(:get, "/channels/#{channel_id}/messages/pins", params: params) do
      {:ok,
       %{
         items: Enum.map(data["items"] || [], &new_pin/1),
         has_more: data["has_more"] || false
       }}
    end
  end

  defp new_pin(item) do
    %{
      pinned_at: item["pinned_at"],
      message: Message.new(item["message"])
    }
  end

  @doc "Pins a message."
  @spec pin_message(Api.id(), Api.id(), keyword()) :: Api.result()
  def pin_message(channel_id, message_id, opts \\ []) do
    Client.request(:put, "/channels/#{channel_id}/messages/pins/#{message_id}",
      reason: opts[:reason]
    )
  end

  @doc "Unpins a message."
  @spec unpin_message(Api.id(), Api.id(), keyword()) :: Api.result()
  def unpin_message(channel_id, message_id, opts \\ []) do
    Client.request(:delete, "/channels/#{channel_id}/messages/pins/#{message_id}",
      reason: opts[:reason]
    )
  end
end
