defmodule Lingo.Cache.Member do
  @moduledoc "Cached guild members. See `Lingo.Cache` for enabling and configuring the cache."

  alias Lingo.Cache.Tables

  @doc "A guild member, with their user, or `nil`."
  @spec get(Lingo.Api.id(), Lingo.Api.id()) :: Lingo.Type.Member.t() | nil
  def get(guild_id, user_id) do
    case Tables.get(:members, {guild_id, user_id}) do
      nil -> nil
      member -> with_user(member, user_id)
    end
  end

  @doc "A guild's cached members, with their users."
  @spec list(Lingo.Api.id()) :: [Lingo.Type.Member.t()]
  def list(guild_id) do
    :members
    |> Tables.select([{{{guild_id, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {user_id, member} -> with_user(member, user_id) end)
  end

  # the independently cached user is newer than the copy kept with the member
  defp with_user(member, user_id),
    do: %{member | user: Lingo.Cache.User.get(user_id) || member.user}
end
