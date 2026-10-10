defmodule Lingo.Gateway.ShardManager.Pool do
  @moduledoc false

  # The shard processes a ShardManager runs: starting them, monitored, and
  # forgetting them. Every function takes and returns the manager's state.

  alias Lingo.Gateway.{Shard, Sharding}

  # Identify pacing is enforced per bucket by reserve_identify/1, so shards can
  # all be started right away without blocking this process.
  def start_all(state, plan, count) do
    ids = Sharding.ids(state.configured_ids, count)

    state = %{
      state
      | gateway_url: plan.url,
        max_concurrency: plan.max_concurrency,
        shard_count: count,
        expected_shard_count: length(ids)
    }

    Enum.reduce(ids, state, fn shard_id, state ->
      case start(state, shard_id) do
        {:ok, state} -> state
        {:error, _reason} -> state
      end
    end)
  end

  def start(state, shard_id) do
    opts = [
      bot: state.bot,
      shard_id: shard_id,
      shard_count: state.shard_count,
      token: state.token,
      intents: state.intents,
      gateway_url: state.gateway_url,
      presence: state.presence
    ]

    with {:ok, pid} <- DynamicSupervisor.start_child(state.shard_supervisor, {Shard, opts}) do
      ref = Process.monitor(pid)

      {:ok,
       %{
         state
         | shards: Map.put(state.shards, shard_id, pid),
           shard_refs: Map.put(state.shard_refs, ref, shard_id)
       }}
    end
  end

  def forget(state, shard_id),
    do: %{
      state
      | shards: Map.delete(state.shards, shard_id),
        ready_shards: Map.delete(state.ready_shards, shard_id)
    }
end
