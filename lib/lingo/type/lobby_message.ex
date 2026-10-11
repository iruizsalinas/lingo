defmodule Lingo.Type.LobbyMessage do
  @moduledoc """
  A message sent in a Social SDK lobby. `metadata` is the string map the
  sender attached and `moderation_metadata` the one set with
  `Lingo.Api.Lobby.update_moderation_metadata/3`; `lobby_member` holds the
  author's `additional_name` when they had one. `timestamp` and
  `edited_timestamp` come with updates.
  """

  alias Lingo.Type.{Parse, User}

  @type t :: %__MODULE__{
          id: String.t(),
          type: integer(),
          content: String.t(),
          lobby_id: String.t(),
          channel_id: String.t(),
          author: User.t() | nil,
          lobby_member: %{additional_name: String.t()} | nil,
          metadata: %{String.t() => String.t()} | nil,
          moderation_metadata: %{String.t() => String.t()} | nil,
          flags: integer(),
          application_id: String.t() | nil,
          timestamp: DateTime.t() | nil,
          edited_timestamp: DateTime.t() | nil
        }

  defstruct [
    :id,
    :content,
    :lobby_id,
    :channel_id,
    :author,
    :lobby_member,
    :metadata,
    :moderation_metadata,
    :application_id,
    :timestamp,
    :edited_timestamp,
    type: 0,
    flags: 0
  ]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      type: data["type"] || 0,
      content: data["content"],
      lobby_id: data["lobby_id"],
      channel_id: data["channel_id"],
      author: User.new(data["author"]),
      lobby_member: lobby_member(data["lobby_member"]),
      metadata: data["metadata"],
      moderation_metadata: data["moderation_metadata"],
      flags: data["flags"] || 0,
      application_id: data["application_id"],
      timestamp: Parse.timestamp(data["timestamp"]),
      edited_timestamp: Parse.timestamp(data["edited_timestamp"])
    }
  end

  defp lobby_member(nil), do: nil
  defp lobby_member(data), do: %{additional_name: data["additional_name"]}
end
