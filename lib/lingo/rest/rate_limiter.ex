defmodule Lingo.Rest.RateLimiter do
  @moduledoc false

  use GenServer

  alias Lingo.Instance
  alias Lingo.Rest.Buckets

  def start_link(opts) do
    bot = Keyword.fetch!(opts, :bot)
    GenServer.start_link(__MODULE__, bot, name: Instance.process_name(bot, __MODULE__))
  end

  defp server, do: Instance.process_name(__MODULE__)

  @spec acquire(String.t(), timeout()) :: {:ok, String.t()} | :timeout
  def acquire(route_key, timeout \\ :infinity) do
    bucket_key = Buckets.resolve(route_key)

    try do
      GenServer.call(server(), {:acquire, bucket_key}, timeout)
      {:ok, bucket_key}
    catch
      :exit, {:timeout, _} ->
        # the lock may have been granted after the timeout fired; the late reply
        # is dropped, so cancel either drops us from the queue or releases it
        GenServer.cast(server(), {:cancel, bucket_key, self()})
        :timeout
    end
  end

  @spec release(String.t()) :: :ok
  def release(bucket_key) do
    GenServer.cast(server(), {:release, bucket_key})
  end

  @impl true
  def init(bot) do
    Instance.put_current(bot)

    Instance.put(bot, :rate_limiter, %{
      buckets: :ets.new(:buckets, [:public, :set, {:read_concurrency, true}]),
      bucket_map: :ets.new(:bucket_map, [:public, :set, {:read_concurrency, true}]),
      global: :ets.new(:global, [:public, :set])
    })

    schedule_cleanup()
    {:ok, %{locks: %{}, monitors: %{}}}
  end

  @impl true
  def handle_call({:acquire, bucket_key}, {pid, _} = from, state) do
    case Map.get(state.locks, bucket_key) do
      nil ->
        ref = Process.monitor(pid)
        locks = Map.put(state.locks, bucket_key, {pid, ref, :queue.new()})
        monitors = Map.put(state.monitors, ref, {:owner, bucket_key})
        {:reply, :ok, %{state | locks: locks, monitors: monitors}}

      {_owner, _owner_ref, queue} ->
        ref = Process.monitor(pid)
        queue = :queue.in(from, queue)
        locks = Map.put(state.locks, bucket_key, put_elem(state.locks[bucket_key], 2, queue))
        monitors = Map.put(state.monitors, ref, {:waiter, bucket_key, from})
        {:noreply, %{state | locks: locks, monitors: monitors}}
    end
  end

  @impl true
  def handle_cast({:release, bucket_key}, state) do
    {:noreply, do_release(state, bucket_key)}
  end

  def handle_cast({:cancel, bucket_key, pid}, state) do
    case Map.get(state.locks, bucket_key) do
      nil ->
        {:noreply, state}

      {^pid, _owner_ref, _queue} ->
        {:noreply, do_release(state, bucket_key)}

      {owner, owner_ref, queue} ->
        queue = :queue.filter(fn {waiter, _} -> waiter != pid end, queue)
        locks = Map.put(state.locks, bucket_key, {owner, owner_ref, queue})

        monitors =
          state.monitors
          |> Enum.filter(fn
            {_ref, {:waiter, ^bucket_key, {^pid, _}}} -> true
            _ -> false
          end)
          |> Enum.reduce(state.monitors, fn {ref, _}, acc ->
            Process.demonitor(ref, [:flush])
            Map.delete(acc, ref)
          end)

        {:noreply, %{state | locks: locks, monitors: monitors}}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _} ->
        {:noreply, state}

      {{:owner, bucket_key}, monitors} ->
        state = %{state | monitors: monitors}
        Process.demonitor(ref, [:flush])
        {:noreply, do_release(state, bucket_key)}

      {{:waiter, bucket_key, from}, monitors} ->
        state = %{state | monitors: monitors}
        Process.demonitor(ref, [:flush])

        case Map.get(state.locks, bucket_key) do
          nil ->
            {:noreply, state}

          {owner, owner_ref, queue} ->
            queue = :queue.filter(fn f -> f != from end, queue)
            locks = Map.put(state.locks, bucket_key, {owner, owner_ref, queue})
            {:noreply, %{state | locks: locks}}
        end
    end
  end

  def handle_info(:cleanup, state) do
    Buckets.cleanup()
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 60_000)
  end

  defp do_release(state, bucket_key) do
    case Map.get(state.locks, bucket_key) do
      nil ->
        state

      {_owner, owner_ref, queue} ->
        Process.demonitor(owner_ref, [:flush])
        monitors = Map.delete(state.monitors, owner_ref)

        case next_live_waiter(queue, monitors) do
          {nil, monitors} ->
            locks = Map.delete(state.locks, bucket_key)
            %{state | locks: locks, monitors: monitors}

          {{next_from, next_ref}, queue, monitors} ->
            {next_pid, _} = next_from
            GenServer.reply(next_from, :ok)
            monitors = Map.put(monitors, next_ref, {:owner, bucket_key})
            locks = Map.put(state.locks, bucket_key, {next_pid, next_ref, queue})
            %{state | locks: locks, monitors: monitors}
        end
    end
  end

  defp next_live_waiter(queue, monitors) do
    case :queue.out(queue) do
      {:empty, _} ->
        {nil, monitors}

      {{:value, from}, rest} ->
        # find the monitor ref for this waiter
        ref =
          Enum.find_value(monitors, fn
            {r, {:waiter, _, ^from}} -> r
            _ -> nil
          end)

        if ref && Process.alive?(elem(from, 0)) do
          monitors = Map.delete(monitors, ref)
          {{from, ref}, rest, monitors}
        else
          if ref, do: Process.demonitor(ref, [:flush])
          monitors = if ref, do: Map.delete(monitors, ref), else: monitors
          next_live_waiter(rest, monitors)
        end
    end
  end
end
