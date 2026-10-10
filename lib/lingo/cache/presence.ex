defmodule Lingo.Cache.Presence do
  @moduledoc "Cached presences. See `Lingo.Cache` for enabling and configuring the cache."

  alias Lingo.Cache.Tables

  @doc "A member's presence, or `nil`."
  @spec get(Lingo.Api.id(), Lingo.Api.id()) :: Lingo.Type.Presence.t() | nil
  def get(guild_id, user_id) do
    case Tables.get(:presences, {guild_id, user_id}) do
      nil -> nil
      presence -> with_user(presence, user_id)
    end
  end

  @doc "A guild's cached presences."
  @spec list(Lingo.Api.id()) :: [Lingo.Type.Presence.t()]
  def list(guild_id) do
    :presences
    |> Tables.select([{{{guild_id, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {user_id, presence} -> with_user(presence, user_id) end)
  end

  defp with_user(presence, user_id) do
    user = Lingo.Cache.User.get(user_id) || presence.user || %Lingo.Type.User{id: user_id}
    %{presence | user: user}
  end
end
