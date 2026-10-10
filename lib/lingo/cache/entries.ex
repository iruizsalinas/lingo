defmodule Lingo.Cache.Entries do
  @moduledoc false

  # One owner serializes managed writes. Only configured policies allocate
  # indexes, and only ordinary entries enter eviction/expiration indexes.
  alias Lingo.Cache.{Policy, Storage}

  def new(policy) do
    ttl? = policy.ttl != :infinity
    bounded? = policy.max_entries != :infinity or policy.scope_limit != :infinity

    %{
      table: Storage.table(policy, true),
      meta: table(:set, if(ttl?, do: :protected, else: :private), ttl?),
      order: if(bounded?, do: table(:ordered_set, :private, false)),
      expiry: if(ttl?, do: table(:ordered_set, :private, false)),
      counts: %{},
      policy: policy
    }
  end

  defp table(type, access, reads?),
    do: :ets.new(__MODULE__, [type, access, read_concurrency: reads?])

  def put(state, resource, {key, value}, kept?) do
    state = state |> sweep() |> delete(key)

    seq =
      if state.order || state.expiry, do: System.unique_integer([:monotonic, :positive]), else: 0

    scope = if state.policy.scope_limit != :infinity, do: Policy.scope(resource, key, value)
    expires = if kept? or state.expiry == nil, do: :infinity, else: now() + state.policy.ttl
    :ets.insert(state.meta, {key, seq, scope, expires, kept?})
    :ets.insert(state.table, {key, value})

    unless kept? do
      for index <- indexes(state, seq, scope), do: :ets.insert(state.order, {index, key})
      if expires != :infinity, do: :ets.insert(state.expiry, {{expires, seq}, key})
    end

    state = count(state, scope, 1)

    state
    |> enforce({:scope, scope}, state.policy.scope_limit)
    |> enforce(:all, state.policy.max_entries)
  end

  defp indexes(state, seq, scope) do
    global = if state.policy.max_entries == :infinity, do: [], else: [{:all, seq}]
    if state.policy.scope_limit == :infinity, do: global, else: [{{:scope, scope}, seq} | global]
  end

  def delete(state, key) do
    case :ets.take(state.meta, key) do
      [{^key, seq, scope, expires, kept?}] ->
        :ets.delete(state.table, key)

        unless kept? do
          for index <- indexes(state, seq, scope), do: :ets.delete(state.order, index)
        end

        if expires != :infinity, do: :ets.delete(state.expiry, {expires, seq})
        count(state, scope, -1)

      [] ->
        state
    end
  end

  defp count(%{policy: %{scope_limit: :infinity}} = state, _, _), do: state

  defp count(state, scope, delta) do
    counts = Map.update(state.counts, scope, delta, &(&1 + delta))
    counts = if counts[scope] == 0, do: Map.delete(counts, scope), else: counts
    %{state | counts: counts}
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

  def sweep(state, budget \\ 100)
  def sweep(%{expiry: nil} = state, _), do: state

  def sweep(state, budget) do
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
        table != nil,
        do: :ets.delete_all_objects(table)

    %{state | counts: %{}}
  end

  def now, do: System.monotonic_time(:millisecond)
end
