defmodule Lingo.Type.Lobby do
  @moduledoc """
  A Social SDK lobby: a group of players. `metadata` is the string map the
  lobby was given; `linked_channel` is the guild text channel it's linked to,
  if any.
  """

  alias Lingo.Type.{Channel, LobbyMember, Parse}

  @type t :: %__MODULE__{
          id: String.t(),
          application_id: String.t(),
          metadata: %{String.t() => String.t()} | nil,
          members: [LobbyMember.t()],
          linked_channel: Channel.t() | nil
        }

  defstruct [:id, :application_id, :metadata, :linked_channel, members: []]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      application_id: data["application_id"],
      metadata: data["metadata"],
      members: Parse.list(data["members"], &LobbyMember.new/1),
      linked_channel: Channel.new(data["linked_channel"])
    }
  end
end
