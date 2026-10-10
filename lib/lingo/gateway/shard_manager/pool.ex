defmodule Lingo.Gateway.ShardManager.Pool do
  @moduledoc false

  # One generation of shards, all under the same shard count: the live one,
  # or the one a reshard is bringing up. Starting a shard takes the manager's
  # state, for the options every shard shares.

  alias Lingo.Gateway.Shard

  defstruct count: 0, expected: 0, shards: %{}, refs: %{}, ready: MapSet.new()

  @type t :: %__MODULE__{
          count: non_neg_integer(),
          expected: non_neg_integer(),
          shards: %{non_neg_integer() => pid()},
          refs: %{reference() => non_neg_integer()},
          ready: MapSet.t(non_neg_integer())
        }

  # Identify pacing is enforced per bucket by Lingo.Gateway.Identify, so
  # shards can all be started right away without blocking the manager.
  @spec start_all(t(), [non_neg_integer()], map()) :: t()
  def start_all(pool, ids, manager) do
    Enum.reduce(ids, %{pool | expected: length(ids)}, fn shard_id, pool ->
      case start(pool, shard_id, manager) do
        {:ok, pool} -> pool
        {:error, _reason} -> pool
      end
    end)
  end

  @spec start(t(), non_neg_integer(), map()) :: {:ok, t()} | {:error, term()}
  def start(pool, shard_id, manager) do
    opts = [
      bot: manager.bot,
      shard_id: shard_id,
      shard_count: pool.count,
      token: manager.token,
      intents: manager.intents,
      gateway_url: manager.gateway_url,
      presence: manager.presence,
      encoding: manager.encoding,
      compression: manager.compression
    ]

    # temporary: the manager restarts shards itself, so they're never doubled
    spec = Supervisor.child_spec({Shard, opts}, restart: :temporary)

    with {:ok, pid} <- DynamicSupervisor.start_child(manager.shard_supervisor, spec) do
      ref = Process.monitor(pid)

      {:ok,
       %{
         pool
         | shards: Map.put(pool.shards, shard_id, pid),
           refs: Map.put(pool.refs, ref, shard_id)
       }}
    end
  end

  @doc "Forgets the shard a monitor belonged to, returning its id (nil if not ours)."
  @spec pop_ref(t(), reference()) :: {non_neg_integer() | nil, t()}
  def pop_ref(pool, ref) do
    case Map.pop(pool.refs, ref) do
      {nil, _refs} -> {nil, pool}
      {shard_id, refs} -> {shard_id, forget(%{pool | refs: refs}, shard_id)}
    end
  end

  @spec ready(t(), non_neg_integer()) :: t()
  def ready(pool, shard_id), do: %{pool | ready: MapSet.put(pool.ready, shard_id)}

  @spec all_ready?(t()) :: boolean()
  def all_ready?(pool), do: pool.expected > 0 and MapSet.size(pool.ready) >= pool.expected

  @doc "Stops one shard, without it being restarted."
  @spec stop_shard(t(), non_neg_integer(), pid()) :: t()
  def stop_shard(pool, shard_id, supervisor) do
    {refs, others} = Map.split_with(pool.refs, fn {_ref, id} -> id == shard_id end)
    Enum.each(refs, fn {ref, _id} -> Process.demonitor(ref, [:flush]) end)
    if pid = pool.shards[shard_id], do: DynamicSupervisor.terminate_child(supervisor, pid)
    forget(%{pool | refs: others}, shard_id)
  end

  @doc "Stops a shard and starts it again."
  @spec restart(t(), non_neg_integer(), map()) :: {:ok | {:error, term()}, t()}
  def restart(pool, shard_id, manager) do
    pool = stop_shard(pool, shard_id, manager.shard_supervisor)

    case start(pool, shard_id, manager) do
      {:ok, pool} -> {:ok, pool}
      {:error, reason} -> {{:error, reason}, pool}
    end
  end

  @doc "Every shard's connection state, asked in parallel."
  @spec statuses(t()) :: %{non_neg_integer() => atom()}
  def statuses(pool) do
    pool.shards
    |> Task.async_stream(fn {id, shard} -> {id, Shard.status(shard)} end,
      timeout: 6_000,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.reduce(%{}, fn
      {:ok, {id, status}}, acc -> Map.put(acc, id, status)
      _timed_out, acc -> acc
    end)
  end

  @doc "Stops every shard of the generation."
  @spec stop(t(), pid()) :: t()
  def stop(pool, supervisor),
    do: Enum.reduce(Map.keys(pool.shards), pool, &stop_shard(&2, &1, supervisor))

  defp forget(pool, shard_id),
    do: %{
      pool
      | shards: Map.delete(pool.shards, shard_id),
        ready: MapSet.delete(pool.ready, shard_id)
    }
end
