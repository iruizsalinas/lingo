defmodule Lingo.Cache.Channel do
  @moduledoc "Cached channels, threads and DMs. See `Lingo.Cache` for enabling and configuring the cache."

  alias Lingo.Cache.{Cluster, Tables}

  @doc "A channel or thread, or `nil`. `cluster: true` asks the other nodes on a miss."
  @spec get(Lingo.Api.id(), keyword()) :: Lingo.Type.Channel.t() | nil
  def get(id, opts \\ []), do: Cluster.any(opts, Tables, :get, [:channels, id])
end
