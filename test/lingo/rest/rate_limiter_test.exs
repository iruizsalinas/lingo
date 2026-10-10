defmodule Lingo.Rest.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Lingo.Rest.RateLimiter

  setup do
    %{bot: Lingo.TestBot.start(start: [:rate_limiter])}
  end

  defp limiter, do: Process.whereis(Lingo.Instance.process_name(Lingo.Rest.RateLimiter))

  describe "acquire/release" do
    test "acquire returns the bucket key" do
      {:ok, key} = RateLimiter.acquire("GET:/channels/500/messages")
      assert is_binary(key)
      RateLimiter.release(key)
    end

    test "acquire grants immediately when bucket is free" do
      start = System.monotonic_time(:millisecond)
      {:ok, key} = RateLimiter.acquire("GET:/channels/600/test")
      elapsed = System.monotonic_time(:millisecond) - start

      assert elapsed < 50
      RateLimiter.release(key)
    end

    test "second acquire blocks until first releases" do
      {:ok, key} = RateLimiter.acquire("GET:/channels/700/test")

      task =
        Task.async(fn ->
          start = System.monotonic_time(:millisecond)
          {:ok, k} = RateLimiter.acquire("GET:/channels/700/test")
          elapsed = System.monotonic_time(:millisecond) - start
          RateLimiter.release(k)
          elapsed
        end)

      # hold the lock for 200ms
      Process.sleep(200)
      RateLimiter.release(key)

      elapsed = Task.await(task, 5_000)
      assert elapsed >= 150
    end

    test "different buckets don't block each other" do
      {:ok, key1} = RateLimiter.acquire("GET:/channels/800/test")

      start = System.monotonic_time(:millisecond)
      {:ok, key2} = RateLimiter.acquire("GET:/channels/900/test")
      elapsed = System.monotonic_time(:millisecond) - start

      assert elapsed < 50

      RateLimiter.release(key1)
      RateLimiter.release(key2)
    end

    test "FIFO ordering is preserved" do
      {:ok, key} = RateLimiter.acquire("GET:/channels/1000/test")
      order = :ets.new(:order, [:set, :public])

      t1 =
        Task.async(fn ->
          {:ok, k} = RateLimiter.acquire("GET:/channels/1000/test")
          :ets.insert(order, {:t1, System.monotonic_time(:millisecond)})
          # hold it briefly so t2's acquire time is distinguishable
          Process.sleep(10)
          RateLimiter.release(k)
        end)

      # small delay so t1 queues before t2
      Process.sleep(20)

      t2 =
        Task.async(fn ->
          {:ok, k} = RateLimiter.acquire("GET:/channels/1000/test")
          :ets.insert(order, {:t2, System.monotonic_time(:millisecond)})
          RateLimiter.release(k)
        end)

      Process.sleep(50)
      RateLimiter.release(key)

      Task.await(t1, 5_000)
      Task.await(t2, 5_000)

      [{:t1, time1}] = :ets.lookup(order, :t1)
      [{:t2, time2}] = :ets.lookup(order, :t2)
      assert time1 < time2
    end

    test "lock is released when owner process dies", %{bot: bot} do
      {pid, ref} =
        spawn_monitor(fn ->
          Lingo.put_bot(bot)
          RateLimiter.acquire("GET:/channels/1100/test")
          # die without releasing
          :ok
        end)

      receive do
        {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
      end

      # small delay for the DOWN message to reach the GenServer
      Process.sleep(50)

      start = System.monotonic_time(:millisecond)
      {:ok, key} = RateLimiter.acquire("GET:/channels/1100/test")
      elapsed = System.monotonic_time(:millisecond) - start

      assert elapsed < 100
      RateLimiter.release(key)
    end

    test "dead waiter is skipped, next live waiter gets the lock", %{bot: bot} do
      {:ok, key} = RateLimiter.acquire("GET:/channels/1200/test")

      # waiter 1 will die while waiting
      {pid1, ref1} =
        spawn_monitor(fn ->
          Lingo.put_bot(bot)
          RateLimiter.acquire("GET:/channels/1200/test")
        end)

      Process.sleep(20)

      # waiter 2 is alive
      t2 =
        Task.async(fn ->
          {:ok, k} = RateLimiter.acquire("GET:/channels/1200/test")
          RateLimiter.release(k)
          :got_lock
        end)

      Process.sleep(20)

      # kill waiter 1
      Process.exit(pid1, :kill)

      receive do
        {:DOWN, ^ref1, :process, ^pid1, :killed} -> :ok
      end

      Process.sleep(50)
      RateLimiter.release(key)

      # waiter 2 should get it (waiter 1 was dead, skipped)
      assert Task.await(t2, 5_000) == :got_lock
    end
  end

  describe "acquire/2 timeout" do
    test "times out while queued and leaves the queue" do
      {:ok, key} = RateLimiter.acquire("GET:/channels/1600/test")

      assert RateLimiter.acquire("GET:/channels/1600/test", 50) == :timeout

      # the timed out waiter must not inherit the lock
      task =
        Task.async(fn ->
          {:ok, k} = RateLimiter.acquire("GET:/channels/1600/test")
          RateLimiter.release(k)
          :got_lock
        end)

      Process.sleep(20)
      RateLimiter.release(key)

      assert Task.await(task, 1_000) == :got_lock
      assert :sys.get_state(limiter()).locks == %{}
    end

    test "cancel releases a lock that was granted after the timeout" do
      {:ok, key} = RateLimiter.acquire("GET:/channels/1700/test")
      waiter = self()

      # simulate the race: the waiter is granted the lock, then cancels
      GenServer.cast(limiter(), {:cancel, key, waiter})
      assert :sys.get_state(limiter()).locks == %{}

      {:ok, key} = RateLimiter.acquire("GET:/channels/1700/test", 50)
      RateLimiter.release(key)
    end
  end
end
