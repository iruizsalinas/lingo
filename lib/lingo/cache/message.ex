defmodule Lingo.Cache.Message do
  @moduledoc "Recent messages. See `Lingo.Cache` for enabling and configuring the cache."

  alias Lingo.Cache.{Cluster, Tables}

  @doc "A recent message, or `nil`. `cluster: true` asks the other nodes on a miss."
  @spec get(Lingo.Api.id(), Lingo.Api.id(), keyword()) :: Lingo.Type.Message.t() | nil
  def get(channel_id, message_id, opts \\ []),
    do: Cluster.any(opts, Tables, :get, [:messages, {channel_id, message_id}])

  @doc "A channel's cached messages, oldest first. Takes `cluster: true` as `get/3` does."
  @spec list(Lingo.Api.id(), keyword()) :: [Lingo.Type.Message.t()]
  def list(channel_id, opts \\ []) do
    opts
    |> Cluster.any(Tables, :select, [:messages, [{{{channel_id, :_}, :"$1"}, [], [:"$1"]}]])
    |> Enum.sort_by(&Lingo.Snowflake.to_integer(&1.id))
  end
end
