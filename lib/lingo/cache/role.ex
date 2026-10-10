defmodule Lingo.Cache.Role do
  @moduledoc "Cached roles. See `Lingo.Cache` for enabling and configuring the cache."

  alias Lingo.Cache.{Cluster, Tables}

  @doc "A role, or `nil`. `cluster: true` asks the node running the guild's shard on a miss."
  @spec get(Lingo.Api.id(), Lingo.Api.id(), keyword()) :: Lingo.Type.Role.t() | nil
  def get(guild_id, role_id, opts \\ []),
    do: Cluster.guild(guild_id, opts, Tables, :get, [:roles, {guild_id, role_id}])

  @doc "A guild's roles. Takes `cluster: true` as `get/3` does."
  @spec list(Lingo.Api.id(), keyword()) :: [Lingo.Type.Role.t()]
  def list(guild_id, opts \\ []) do
    Cluster.guild(guild_id, opts, Tables, :select, [
      :roles,
      [{{{guild_id, :_}, :"$1"}, [], [:"$1"]}]
    ])
  end
end
