defmodule Lingo.Cache.Channel do
  @moduledoc "Cached channels, threads and DMs. See `Lingo.Cache` for enabling and configuring the cache."

  alias Lingo.Cache.Tables

  @doc "A channel or thread, or `nil`."
  @spec get(Lingo.Api.id()) :: Lingo.Type.Channel.t() | nil
  def get(id), do: Tables.get(:channels, id)
end
