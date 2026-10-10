defmodule Lingo.Cache.Guild do
  @moduledoc "Cached guilds. See `Lingo.Cache` for enabling and configuring the cache."

  alias Lingo.Cache.{Cluster, Tables}

  @doc "A guild, or `nil`. `cluster: true` asks the node running its shard on a miss."
  @spec get(Lingo.Api.id(), keyword()) :: Lingo.Type.Guild.t() | nil
  def get(id, opts \\ []), do: Cluster.guild(id, opts, Tables, :get, [:guilds, id])

  @doc "Every cached guild. `cluster: true` gathers them from every node the bot runs on."
  @spec list(keyword()) :: [Lingo.Type.Guild.t()]
  def list(opts \\ []),
    do: Cluster.all(opts, Tables, :select, [:guilds, [{{:_, :"$1"}, [], [:"$1"]}]])
end
