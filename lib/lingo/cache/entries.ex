defmodule Lingo.Cache.Entries do
  @moduledoc false

  # Managed mutations are serialized by Tables. Reads remain ETS lookups.
  # Only ordinary entries enter the eviction/expiration indexes.
  alias Lingo.Cache.Policy

  def new(policy) do
    %{
      table: table(:set),
      meta: table(:set),
      order: table(:ordered_set),
      expiry: table(:ordered_set),
      counts: %{},
      policy: policy
    }
  end

  defp table(type), do: :ets.new(__MODULE__, [type, :public, read_concurrency: true])

  def put(state, resource, {key, value}, kept?) do
    state = state |> sweep() |> delete(key)
    seq = System.unique_integer([:monotonic, :positive])
    scope = Policy.scope(resource, key, value)
    ttl = state.policy.ttl
    expires = if kept? or ttl == :infinity, do: :infinity, else: now() + ttl
    :ets.insert(state.meta, {key, seq, scope, expires, kept?})
    :ets.insert(state.table, {key, value})

    unless kept? do
      :ets.insert(state.order, [{{:all, seq}, key}, {{{:scope, scope}, seq}, key}])
      if expires != :infinity, do: :ets.insert(state.expiry, {{expires, seq}, key})
    end

    state = %{state | counts: Map.update(state.counts, scope, 1, &(&1 + 1))}

    state
    |> enforce({:scope, scope}, state.policy.scope_limit)
    |> enforce(:all, state.policy.max_entries)
  end

  def delete(state, key) do
    case :ets.take(state.meta, key) do
      [{^key, seq, scope, expires, _}] ->
        :ets.delete(state.table, key)
        :ets.delete(state.order, {:all, seq})
        :ets.delete(state.order, {{:scope, scope}, seq})
        if expires != :infinity, do: :ets.delete(state.expiry, {expires, seq})
        counts = Map.update!(state.counts, scope, &(&1 - 1))
        counts = if counts[scope] == 0, do: Map.delete(counts, scope), else: counts
        %{state | counts: counts}

      [] ->
        state
    end
  end

  defp enforce(state, _, :infinity), do: state

  defp enforce(state, scope, limit) do
    count =
      if scope == :all,
        do: :ets.info(state.table, :size),
        else: Map.get(state.counts, elem(scope, 1), 0)

    if count > limit do
      case :ets.next(state.order, {scope, 0}) do
        {^scope, _} = index ->
          [{^index, key}] = :ets.lookup(state.order, index)
          state |> delete(key) |> enforce(scope, limit)

        _ ->
          state
      end
    else
      state
    end
  end

  def live?(state, key) do
    case :ets.lookup(state.meta, key) do
      [{^key, _, _, :infinity, _}] -> true
      [{^key, _, _, expires, _}] -> expires > now()
      [] -> false
    end
  end

  def sweep(state, budget \\ 100) do
    case :ets.first(state.expiry) do
      {expires, _} = index when budget > 0 ->
        if expires <= now() do
          [{^index, key}] = :ets.lookup(state.expiry, index)
          sweep(delete(state, key), budget - 1)
        else
          state
        end

      _ ->
        state
    end
  end

  def clear(state) do
    for table <- [state.table, state.meta, state.order, state.expiry],
        do: :ets.delete_all_objects(table)

    %{state | counts: %{}}
  end

  def now, do: System.monotonic_time(:millisecond)
end
