defmodule Lingo.Event.Ready do
  @moduledoc """
  The payload of `:ready`: a shard started a new session.

  It fires for every shard, and again whenever a shard has to start over
  instead of resuming (a resume fires `:resumed`). To run something once
  every shard is up, use `Lingo.Gateway.await_ready/1`. `guilds` are the
  shard's guilds, unavailable until their `:guild_create` arrives.
  """

  alias Lingo.Type.{Guild, User}

  @type t :: %__MODULE__{
          shard_id: non_neg_integer(),
          shard_count: pos_integer(),
          session_id: String.t(),
          user: User.t(),
          guilds: [Guild.t()],
          application_id: String.t(),
          application_flags: integer() | nil
        }

  defstruct [
    :session_id,
    :user,
    :application_id,
    :application_flags,
    shard_id: 0,
    shard_count: 1,
    guilds: []
  ]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    [shard_id, shard_count] = data["shard"] || [0, 1]

    %__MODULE__{
      shard_id: shard_id,
      shard_count: shard_count,
      session_id: data["session_id"],
      user: User.new(data["user"]),
      guilds: Enum.map(data["guilds"] || [], &Guild.new/1),
      application_id: get_in(data, ["application", "id"]),
      application_flags: get_in(data, ["application", "flags"])
    }
  end
end
