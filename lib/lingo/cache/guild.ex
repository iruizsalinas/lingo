defmodule Lingo.Cache.Guild do
  @moduledoc "Cached guilds. See `Lingo.Cache` for enabling and configuring the cache."

  alias Lingo.Cache.{Cluster, Tables}

  @doc "A guild, or `nil`."
  @spec get(Lingo.Api.id()) :: Lingo.Type.Guild.t() | nil
  def get(id), do: Cluster.guild(id, Tables, :get, [:guilds, id])

  @doc "Every cached guild, from every node the bot runs on."
  @spec list() :: [Lingo.Type.Guild.t()]
  def list, do: Cluster.all(Tables, :select, [:guilds, [{{:_, :"$1"}, [], [:"$1"]}]])
end
