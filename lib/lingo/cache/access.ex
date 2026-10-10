defmodule Lingo.Cache.Access do
  @moduledoc false
  alias Lingo.Cache.{Entries, Policy, Selection, Storage}

  def resource(name), do: get_in(Lingo.Instance.get(:cache, %{}), [:resources, name])

  def table(name) do
    case resource(name) do
      nil -> nil
      state -> state.table
    end
  end

  def enabled?(names), do: Enum.any?(List.wrap(names), &(resource(&1) != nil))

  def get(name, key) do
    with state when state != nil <- resource(name),
         [{^key, value}] <- :ets.lookup(state.table, key),
         true <- live?(state, key) do
      Storage.decode(value, state.policy)
    else
      _ -> nil
    end
  end

  defp live?(%{policy: %{ttl: :infinity}}, _), do: true
  defp live?(state, key), do: Entries.live?(state, key)

  def insert(name, {key, value}) do
    if state = resource(name) do
      context =
        if state.policy.filter == :all and state.policy.keep == :none,
          do: nil,
          else: Policy.context(name, key)

      case decide(state.policy, value, context) do
        {true, kept?} ->
          stored = {key, Storage.encode(value, state.policy)}
          mutate(state, {:put, name, stored, kept?}, fn -> :ets.insert(state.table, stored) end)

        {false, _} ->
          delete(name, key)
      end
    else
      :ok
    end
  end

  # Cheap rejection before constructing cache-only values for built-in self policies.
  def wants?(name, id) do
    case resource(name) do
      nil ->
        false

      %{policy: %{filter: :self, keep: keep}} when keep in [:none, :self] ->
        id != nil and id == Lingo.Instance.get(:user_id)

      _ ->
        true
    end
  end

  # Predicates are user code. A failing predicate must not suppress gateway callbacks.
  defp decide(policy, value, context) do
    Policy.decision(policy, value, context)
  rescue
    error ->
      require Logger
      Logger.error("Cache policy failed for #{context.resource}: #{Exception.message(error)}")
      {false, false}
  catch
    _, _ -> {false, false}
  end

  def delete(name, key) do
    if state = resource(name),
      do: mutate(state, {:delete, name, key}, fn -> :ets.delete(state.table, key) end),
      else: :ok
  end

  def select(name, spec) do
    if state = resource(name), do: Selection.select(state, spec), else: []
  end

  def select_delete(name, spec) do
    if state = resource(name) do
      mutate(state, {:select_delete, name, spec}, fn ->
        if state.policy.compact do
          {count, _} = Selection.delete(state, spec)

          count
        else
          :ets.select_delete(state.table, spec)
        end
      end)
    else
      0
    end
  end

  def clear(name) do
    names = if name == :all, do: Policy.resources(), else: [name]

    unless Enum.all?(names, &(&1 in Policy.resources())),
      do: raise(ArgumentError, "unknown cache resource")

    for name <- names, state = resource(name), state != nil do
      mutate(state, {:clear, name}, fn -> :ets.delete_all_objects(state.table) end)
    end

    :ok
  end

  defp mutate(%{meta: _}, message, _fun), do: call(message)
  defp mutate(_, _, fun), do: fun.()

  def call(message),
    do: GenServer.call(Lingo.Instance.process_name(Lingo.Cache.Tables), message, :infinity)
end
