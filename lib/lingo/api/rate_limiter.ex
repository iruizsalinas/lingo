defmodule Lingo.Api.RateLimiter do
  @moduledoc false

  use GenServer

  @buckets :lingo_rate_limits
  @bucket_map :lingo_bucket_map
  @global_table :lingo_global_rate_limit

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @spec acquire(String.t()) :: String.t()
  def acquire(route_key) do
    bucket_key = resolve_bucket(route_key)
    GenServer.call(__MODULE__, {:acquire, bucket_key}, :infinity)
    bucket_key
  end

  @spec release(String.t()) :: :ok
  def release(bucket_key) do
    GenServer.cast(__MODULE__, {:release, bucket_key})
  end

  @spec wait(String.t()) :: :ok
  def wait(route_key) do
    bucket_key = resolve_bucket(route_key)
    do_wait(bucket_key)
  end

  @spec pause_global(non_neg_integer()) :: :ok
  def pause_global(ms) do
    if table_exists?(@global_table) do
      :ets.insert(@global_table, {:paused_until, System.system_time(:millisecond) + ms})
    end

    :ok
  end

  @spec wait_global() :: :ok
  def wait_global do
    if table_exists?(@global_table) do
      case :ets.lookup(@global_table, :paused_until) do
        [{:paused_until, resume_at}] ->
          now = System.system_time(:millisecond)

          if resume_at > now do
            Process.sleep(resume_at - now + 10)
          end

          :ets.delete(@global_table, :paused_until)
          :ok

        [] ->
          :ok
      end
    else
      :ok
    end
  end

  @spec update(String.t(), [{String.t(), String.t()}] | %{String.t() => [String.t()]}) :: :ok
  def update(route_key, headers) do
    if table_exists?(@buckets) do
      hash = get_header(headers, "x-ratelimit-bucket")
      remaining = get_header(headers, "x-ratelimit-remaining")
      reset_after = get_header(headers, "x-ratelimit-reset-after")
      limit = get_header(headers, "x-ratelimit-limit")

      if remaining && reset_after do
        bucket_key =
          if hash do
            major = extract_major(route_key)
            bk = "#{hash}:#{major}"
            :ets.insert(@bucket_map, {route_key, bk})
            bk
          else
            route_key
          end

        remaining_int = parse_int(remaining)
        reset_at = System.system_time(:millisecond) + trunc(parse_float(reset_after) * 1000)
        limit_int = parse_int(limit || "0")

        :ets.insert(@buckets, {bucket_key, remaining_int, reset_at, limit_int})
      end
    end

    :ok
  end

  @impl true
  def init(:ok) do
    :ets.new(@buckets, [:named_table, :public, :set, {:read_concurrency, true}])
    :ets.new(@bucket_map, [:named_table, :public, :set, {:read_concurrency, true}])
    :ets.new(@global_table, [:named_table, :public, :set])
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
    now = System.system_time(:millisecond)

    if table_exists?(@buckets) do
      @buckets
      |> :ets.tab2list()
      |> Enum.each(fn {key, _remaining, reset_at, _limit} ->
        if reset_at < now - 30_000 do
          :ets.delete(@buckets, key)
        end
      end)
    end

    if table_exists?(@bucket_map) do
      # clean mappings that point to expired buckets
      @bucket_map
      |> :ets.tab2list()
      |> Enum.each(fn {route_key, bucket_key} ->
        if :ets.lookup(@buckets, bucket_key) == [] do
          :ets.delete(@bucket_map, route_key)
        end
      end)
    end

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

  defp resolve_bucket(route_key) do
    if table_exists?(@bucket_map) do
      case :ets.lookup(@bucket_map, route_key) do
        [{_, bucket_key}] -> bucket_key
        [] -> route_key
      end
    else
      route_key
    end
  end

  defp do_wait(bucket_key) do
    if table_exists?(@buckets) do
      case :ets.lookup(@buckets, bucket_key) do
        [{^bucket_key, remaining, reset_at, _limit}] when remaining <= 0 ->
          now = System.system_time(:millisecond)

          if reset_at <= now do
            :ets.delete(@buckets, bucket_key)
            :ok
          else
            Process.sleep(reset_at - now + 50)
            do_wait(bucket_key)
          end

        _ ->
          :ok
      end
    else
      :ok
    end
  end

  defp extract_major(route_key) do
    case Regex.run(~r"(?:channels|guilds|webhooks)/(\d+)", route_key) do
      [_, id] -> id
      _ -> "global"
    end
  end

  defp table_exists?(table) do
    :ets.whereis(table) != :undefined
  end

  defp get_header(headers, key) when is_list(headers) do
    case List.keyfind(headers, key, 0) do
      {_, value} -> value
      nil -> nil
    end
  end

  defp get_header(headers, key) when is_map(headers) do
    case Map.get(headers, key) do
      [value | _] -> value
      value when is_binary(value) -> value
      nil -> nil
    end
  end

  defp parse_int(nil), do: 0

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_float(nil), do: 0.0

  defp parse_float(str) when is_binary(str) do
    case Float.parse(str) do
      {f, _} -> f
      :error -> 0.0
    end
  end
end
