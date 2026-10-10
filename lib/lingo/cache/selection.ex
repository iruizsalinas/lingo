defmodule Lingo.Cache.Selection do
  @moduledoc false

  alias Lingo.Cache.{Entries, Storage}
  @batch_size 128

  def select(%{policy: %{compact: false, ttl: :infinity}} = state, spec),
    do: :ets.select(state.table, spec)

  def select(state, spec) do
    state
    |> reduce(spec, [], &Enum.reduce(&1, &2, fn value, acc -> [value | acc] end))
    |> Enum.reverse()
  end

  # Evaluate match specs against fully reconstructed values, including defaults.
  # Narrow candidates by their key before copying/decoding, and bound each batch.
  def reduce(state, spec, acc, fun, live? \\ true) do
    compiled = :ets.match_spec_compile(spec)

    candidates =
      Enum.map(spec, fn
        {{key, _value}, _, _} -> {{key, :_}, [], [:"$_"]}
        _ -> {:_, [], [:"$_"]}
      end)

    :ets.safe_fixtable(state.table, true)

    try do
      traverse(
        :ets.select(state.table, candidates, @batch_size),
        state,
        compiled,
        acc,
        fun,
        live?
      )
    after
      :ets.safe_fixtable(state.table, false)
    end
  end

  defp traverse(:"$end_of_table", _, _, acc, _, _), do: acc

  defp traverse({rows, continuation}, state, compiled, acc, fun, live?) do
    rows =
      for {key, value} <- rows,
          not live? or state.policy.ttl == :infinity or Entries.live?(state, key),
          do: {key, Storage.decode(value, state.policy)}

    acc = fun.(:ets.match_spec_run(rows, compiled), acc)
    traverse(:ets.select(continuation), state, compiled, acc, fun, live?)
  end

  def delete(state, spec) do
    # Preserve first-clause and true-result semantics of ETS select_delete.
    keyed =
      Enum.map(spec, fn {head, guards, body} ->
        {head, guards, [{{{:element, 1, :"$_"}, {:element, 2, :"$_"}, List.last(body)}}]}
      end)

    reduce(
      state,
      keyed,
      {0, state},
      fn results, acc ->
        Enum.reduce(results, acc, fn
          {key, value, true}, {count, current} ->
            {removed, current} = remove(current, key, value)
            {count + removed, current}

          _, current ->
            current
        end)
      end,
      false
    )
  end

  defp remove(%{meta: _} = state, key, _value), do: {1, Entries.delete(state, key)}

  defp remove(state, key, value),
    do: {Storage.delete_version(state.table, key, value, state.policy), state}
end
