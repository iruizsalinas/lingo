defmodule Lingo.Gateway.ShardManager.Reshard do
  @moduledoc false

  # Resharding without downtime. Discord routes a guild to every session
  # with the matching [shard_id, shard_count], so the new shards connect next
  # to the live ones, delivering nothing, and take over once all are ready:
  # their count becomes the live one (which silences the old shards at the
  # same moment) and the old shards stop.
  #
  # Only a bot that runs every shard of an automatic count reshards; a bot
  # split across nodes fixes its count.

  require Logger

  alias Lingo.Gateway.{Connection, Sessions, Shard, Sharding}
  alias Lingo.Gateway.ShardManager.Pool
  alias Lingo.{Instance, Telemetry}

  @default_interval :timer.hours(1)

  @doc "Starts a reshard to Discord's recommended count, when it differs."
  def begin(state), do: maybe_start(state, &(&1 != state.current.count))

  @doc "The periodic check of `auto_reshard`: grows when Discord recommends more shards."
  def check(state) do
    schedule(state)
    maybe_start(state, &(&1 > state.current.count))
  end

  def schedule(%{auto_reshard: nil}), do: :ok

  def schedule(%{auto_reshard: true}),
    do: Process.send_after(self(), :check_reshard, @default_interval)

  def schedule(%{auto_reshard: ms}), do: Process.send_after(self(), :check_reshard, ms)

  defp maybe_start(state, wanted?) do
    with true <- reshardable?(state),
         {:ok, plan} <- Sharding.fetch(),
         true <- wanted?.(plan.recommended),
         true <- enough_identifies?(plan) do
      start(state, plan)
    else
      _no -> state
    end
  end

  defp reshardable?(state) do
    state.configured_count == :auto and state.configured_ids == :all and state.next == nil and
      state.current.count > 0
  end

  defp enough_identifies?(plan) do
    if plan.remaining < plan.recommended,
      do: Logger.warning("Lingo can't reshard: #{plan.remaining} identifies left today")

    plan.remaining >= plan.recommended
  end

  defp start(state, plan) do
    {from, count} = {state.current.count, plan.recommended}
    Logger.info("Lingo resharding from #{from} to #{count} shards")
    Telemetry.execute([:gateway, :reshard, :start], %{}, %{from: from, to: count})

    # twice the time the identifies take, plus some
    identify_ms = div(count, max(plan.max_concurrency, 1)) * 5_500
    timer = Process.send_after(self(), {:reshard_timeout, count}, 2 * identify_ms + 300_000)

    next = Pool.start_all(%Pool{count: count}, Sharding.ids(:all, count), state)
    %{state | next: next, reshard_started: System.monotonic_time(), reshard_timer: timer}
  end

  @doc "Gives up on a reshard whose shards didn't all get ready in time."
  def abort(%{next: %Pool{count: count} = next} = state, count) do
    Logger.warning("Lingo gave up resharding to #{count} shards, not all of them got ready")
    Pool.stop(next, state.shard_supervisor)
    delete_sessions(state.bot, count)
    %{state | next: nil, reshard_started: nil, reshard_timer: nil}
  end

  def abort(state, _count), do: state

  @doc "Hands over to the new shards, once every one of them is ready."
  def switch(%{next: next, current: old} = state) do
    Instance.put(state.bot, :shard_count, next.count)

    for {_id, shard} <- next.shards, pid = Shard.connection(shard), do: Connection.go_live(pid)

    if state.reshard_timer, do: Process.cancel_timer(state.reshard_timer)
    Pool.stop(old, state.shard_supervisor)
    delete_sessions(state.bot, old.count)

    duration = System.monotonic_time() - state.reshard_started
    meta = %{from: old.count, to: next.count}
    Telemetry.execute([:gateway, :reshard, :stop], %{duration: duration}, meta)
    Logger.info("Lingo now runs #{next.count} shards")

    %{state | current: next, next: nil, reshard_started: nil, reshard_timer: nil}
  end

  defp delete_sessions(bot, count),
    do: for(shard_id <- 0..(count - 1)//1, do: Sessions.delete(bot, shard_id, count))
end
