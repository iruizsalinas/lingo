defmodule Lingo.Cache.User do
  @moduledoc "Cached users. See `Lingo.Cache` for enabling and configuring the cache."

  alias Lingo.Cache.Tables

  @doc "A user, or `nil`."
  @spec get(Lingo.Api.id()) :: Lingo.Type.User.t() | nil
  def get(id), do: Tables.get(:users, id)

  @doc "The bot's own user, once the first shard is ready. Kept even with the user cache off."
  @spec get_current() :: Lingo.Type.User.t() | nil
  def get_current, do: Tables.current_user()
end
