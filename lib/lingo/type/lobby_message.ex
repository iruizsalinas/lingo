defmodule Lingo.Type.LobbyMessage do
  @moduledoc """
  A message sent in a Social SDK lobby. `metadata` is the string map the
  sender attached; `timestamp` and `edited_timestamp` come with updates.
  """

  alias Lingo.Type.{Parse, User}

  @type t :: %__MODULE__{
          id: String.t(),
          type: integer(),
          content: String.t(),
          lobby_id: String.t(),
          channel_id: String.t(),
          author: User.t() | nil,
          metadata: %{String.t() => String.t()} | nil,
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
    :metadata,
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
      metadata: data["metadata"],
      flags: data["flags"] || 0,
      application_id: data["application_id"],
      timestamp: Parse.timestamp(data["timestamp"]),
      edited_timestamp: Parse.timestamp(data["edited_timestamp"])
    }
  end
end
