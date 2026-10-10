defmodule Lingo.Cache.Identity do
  @moduledoc false

  def current_user do
    case Lingo.Instance.get(:cache) do
      %{identity: table} ->
        case :ets.lookup(table, :me) do
          [{:me, user}] -> user
          [] -> nil
        end

      _ ->
        nil
    end
  end

  def put_current_user(user) do
    Lingo.Instance.put(Lingo.Instance.current(), :user_id, user.id)
    if cache = Lingo.Instance.get(:cache), do: :ets.insert(cache.identity, {:me, user})
    Lingo.Cache.Access.insert(:users, {user.id, user})
  end
end
