defmodule Lingo.Cache.Role do
  @moduledoc "Cached roles. See `Lingo.Cache` for enabling and configuring the cache."

  alias Lingo.Cache.{Cluster, Tables}

  @doc "A role, or `nil`."
  @spec get(Lingo.Api.id(), Lingo.Api.id()) :: Lingo.Type.Role.t() | nil
  def get(guild_id, role_id),
    do: Cluster.guild(guild_id, Tables, :get, [:roles, {guild_id, role_id}])

  @doc "A guild's roles."
  @spec list(Lingo.Api.id()) :: [Lingo.Type.Role.t()]
  def list(guild_id),
    do:
      Cluster.guild(guild_id, Tables, :select, [:roles, [{{{guild_id, :_}, :"$1"}, [], [:"$1"]}]])
end
