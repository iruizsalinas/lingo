defmodule Lingo.Cache.Channel do
  @moduledoc "Cached channels, threads and DMs. See `Lingo.Cache` for enabling and configuring the cache."

  alias Lingo.Cache.{Cluster, Tables}

  @doc "A channel or thread, or `nil`."
  @spec get(Lingo.Api.id()) :: Lingo.Type.Channel.t() | nil
  def get(id), do: Cluster.any(Tables, :get, [:channels, id])
end
