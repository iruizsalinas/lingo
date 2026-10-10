defmodule Lingo.Event.GuildMembersChunk do
  @moduledoc """
  The payload of `:guild_members_chunk`: one part of the answer to
  `Lingo.Gateway.request_guild_members/2`, numbered by `chunk_index` out of
  `chunk_count`. `not_found` lists the requested user ids that aren't
  members; `nonce` is the request's.
  """

  alias Lingo.Type.{Member, Parse, Presence}

  @type t :: %__MODULE__{
          guild_id: String.t(),
          members: [Member.t()],
          presences: [Presence.t()],
          chunk_index: non_neg_integer(),
          chunk_count: pos_integer(),
          not_found: [String.t()],
          nonce: String.t() | nil
        }

  defstruct [
    :guild_id,
    :nonce,
    members: [],
    presences: [],
    chunk_index: 0,
    chunk_count: 1,
    not_found: []
  ]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    guild_id = data["guild_id"]

    struct(Parse.fields(__MODULE__, data),
      members: Parse.list(data["members"], &Member.new(Parse.put_guild_id(&1, guild_id))),
      presences: Parse.list(data["presences"], &Presence.new(Parse.put_guild_id(&1, guild_id)))
    )
  end
end
