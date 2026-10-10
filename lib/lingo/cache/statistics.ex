defmodule Lingo.Cache.Statistics do
  @moduledoc false
  alias Lingo.Cache.Policy

  def stats do
    Map.new(Policy.resources(), fn name ->
      result =
        case Lingo.Cache.Access.resource(name) do
          nil ->
            %{
              enabled: false,
              policy: false,
              entries: 0,
              kept: 0,
              memory_bytes: 0,
              overflow: %{global: 0, scoped: 0}
            }

          %{meta: _} = state ->
            Map.merge(Lingo.Cache.Access.call({:stats, name}), %{
              enabled: true,
              policy: state.policy
            })

          state ->
            %{
              enabled: true,
              policy: state.policy,
              entries: :ets.info(state.table, :size),
              kept: 0,
              memory_bytes: :ets.info(state.table, :memory) * :erlang.system_info(:wordsize),
              overflow: %{global: 0, scoped: 0}
            }
        end

      {name, result}
    end)
  end

  def entries(state) do
    kept = :ets.select_count(state.meta, [{{:_, :_, :_, :_, true}, [], [true]}])
    size = :ets.info(state.table, :size)

    global =
      if state.policy.max_entries == :infinity,
        do: 0,
        else: max(size - state.policy.max_entries, 0)

    scoped =
      if state.policy.scope_limit == :infinity,
        do: 0,
        else:
          Enum.reduce(state.counts, 0, fn {_, count}, acc ->
            acc + max(count - state.policy.scope_limit, 0)
          end)

    bytes =
      Enum.reduce(
        [state.table, state.meta, state.order, state.expiry],
        0,
        &(:ets.info(&1, :memory) + &2)
      ) * :erlang.system_info(:wordsize)

    %{entries: size, kept: kept, memory_bytes: bytes, overflow: %{global: global, scoped: scoped}}
  end
end
