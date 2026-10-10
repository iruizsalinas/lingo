defmodule Lingo.Cache.Mutation do
  @moduledoc false
  alias Lingo.Cache.{Entries, Selection}

  def apply(state, name, actions) do
    state = Enum.reduce(actions, state, &mutate(&2, name, &1))
    %{state | revision: state.revision + 1}
  end

  defp mutate(%{meta: _} = state, name, {:put, entry, kept?}),
    do: Entries.put(state, name, entry, kept?)

  defp mutate(state, _, {:put, entry, _}) do
    :ets.insert(state.table, entry)
    state
  end

  defp mutate(%{meta: _} = state, _, {:delete, key}), do: Entries.delete(state, key)

  defp mutate(state, _, {:delete, key}) do
    :ets.delete(state.table, key)
    state
  end

  defp mutate(state, _, {:prune, spec}), do: elem(Selection.delete(state, spec), 1)
  defp mutate(%{meta: _} = state, _, :clear), do: Entries.clear(state)

  defp mutate(state, _, :clear) do
    :ets.delete_all_objects(state.table)
    state
  end

  def delete_selected(state, spec) do
    {count, state} = Selection.delete(state, spec)
    {count, %{state | revision: state.revision + 1}}
  end

  def sweep(state) do
    before = :ets.info(state.table, :size)
    state = Entries.sweep(state)

    if :ets.info(state.table, :size) == before,
      do: state,
      else: %{state | revision: state.revision + 1}
  end
end
