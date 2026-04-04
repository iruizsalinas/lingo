defmodule Lingo.Api.RateLimiterTest do
  use ExUnit.Case

  alias Lingo.Api.RateLimiter

  setup do
    start_supervised!(RateLimiter)
    :ok
  end

  describe "update/2 with list headers" do
    test "stores rate limit state and maps route to bucket" do
      headers = [
        {"x-ratelimit-bucket", "abc123"},
        {"x-ratelimit-remaining", "4"},
        {"x-ratelimit-reset-after", "1.5"},
        {"x-ratelimit-limit", "5"}
      ]

      RateLimiter.update("GET:/channels/123/test", headers)

      # route should be mapped to bucket_key "abc123:123"
      [{_, bucket_key}] = :ets.lookup(:lingo_bucket_map, "GET:/channels/123/test")
      assert bucket_key == "abc123:123"

      [{^bucket_key, remaining, reset_at, limit}] = :ets.lookup(:lingo_rate_limits, bucket_key)
      assert remaining == 4
      assert limit == 5
      assert reset_at > System.system_time(:millisecond)
    end

    test "ignores headers without rate limit info" do
      RateLimiter.update("GET:/no/info", [{"content-type", "application/json"}])
      assert :ets.lookup(:lingo_bucket_map, "GET:/no/info") == []
    end
  end

  describe "update/2 with map headers" do
    test "parses map-style headers (as returned by Req)" do
      headers = %{
        "x-ratelimit-bucket" => ["def456"],
        "x-ratelimit-remaining" => ["0"],
        "x-ratelimit-reset-after" => ["2.0"],
        "x-ratelimit-limit" => ["5"]
      }

      RateLimiter.update("GET:/guilds/789/test", headers)

      [{_, bucket_key}] = :ets.lookup(:lingo_bucket_map, "GET:/guilds/789/test")
      assert bucket_key == "def456:789"

      [{^bucket_key, remaining, _reset_at, limit}] = :ets.lookup(:lingo_rate_limits, bucket_key)
      assert remaining == 0
      assert limit == 5
    end
  end

  describe "bucket hash sharing" do
    test "two routes with same bucket hash share rate limits" do
      # simulate two routes on the same channel returning the same bucket hash
      h1 = [
        {"x-ratelimit-bucket", "shared_hash"},
        {"x-ratelimit-remaining", "3"},
        {"x-ratelimit-reset-after", "5.0"},
        {"x-ratelimit-limit", "5"}
      ]

      h2 = [
        {"x-ratelimit-bucket", "shared_hash"},
        {"x-ratelimit-remaining", "1"},
        {"x-ratelimit-reset-after", "5.0"},
        {"x-ratelimit-limit", "5"}
      ]

      RateLimiter.update("GET:/channels/100/messages/:id", h1)
      RateLimiter.update("GET:/channels/100/pins", h2)

      # both map to the same bucket key
      [{_, bk1}] = :ets.lookup(:lingo_bucket_map, "GET:/channels/100/messages/:id")
      [{_, bk2}] = :ets.lookup(:lingo_bucket_map, "GET:/channels/100/pins")
      assert bk1 == bk2
      assert bk1 == "shared_hash:100"

      # the second update overwrote remaining, so wait should see remaining=1
      [{_, remaining, _, _}] = :ets.lookup(:lingo_rate_limits, bk1)
      assert remaining == 1
    end
  end

  describe "wait/1" do
    test "passes immediately when no bucket exists" do
      assert RateLimiter.wait("GET:/unknown/route") == :ok
    end

    test "returns immediately when remaining > 0" do
      headers = [
        {"x-ratelimit-bucket", "b"},
        {"x-ratelimit-remaining", "10"},
        {"x-ratelimit-reset-after", "5.0"},
        {"x-ratelimit-limit", "10"}
      ]

      RateLimiter.update("GET:/channels/200/test", headers)

      start = System.monotonic_time(:millisecond)
      assert RateLimiter.wait("GET:/channels/200/test") == :ok
      elapsed = System.monotonic_time(:millisecond) - start

      assert elapsed < 50
    end

    test "waits when remaining is 0 then passes after reset" do
      headers = [
        {"x-ratelimit-bucket", "exhausted_hash"},
        {"x-ratelimit-remaining", "0"},
        {"x-ratelimit-reset-after", "0.1"},
        {"x-ratelimit-limit", "5"}
      ]

      RateLimiter.update("GET:/channels/300/test", headers)

      start = System.monotonic_time(:millisecond)
      assert RateLimiter.wait("GET:/channels/300/test") == :ok
      elapsed = System.monotonic_time(:millisecond) - start

      assert elapsed >= 80
    end
  end

  describe "wait_global/0" do
    test "passes immediately when not paused" do
      start = System.monotonic_time(:millisecond)
      assert RateLimiter.wait_global() == :ok
      assert System.monotonic_time(:millisecond) - start < 50
    end

    test "blocks until pause expires" do
      RateLimiter.pause_global(100)

      start = System.monotonic_time(:millisecond)
      assert RateLimiter.wait_global() == :ok
      elapsed = System.monotonic_time(:millisecond) - start

      assert elapsed >= 80
    end

    test "pause is cleared after wait" do
      RateLimiter.pause_global(50)
      RateLimiter.wait_global()

      start = System.monotonic_time(:millisecond)
      assert RateLimiter.wait_global() == :ok
      assert System.monotonic_time(:millisecond) - start < 50
    end
  end

  describe "acquire/release" do
    test "acquire returns the bucket key" do
      key = RateLimiter.acquire("GET:/channels/500/messages")
      assert is_binary(key)
      RateLimiter.release(key)
    end

    test "acquire grants immediately when bucket is free" do
      start = System.monotonic_time(:millisecond)
      key = RateLimiter.acquire("GET:/channels/600/test")
      elapsed = System.monotonic_time(:millisecond) - start

      assert elapsed < 50
      RateLimiter.release(key)
    end

    test "second acquire blocks until first releases" do
      key = RateLimiter.acquire("GET:/channels/700/test")

      task =
        Task.async(fn ->
          start = System.monotonic_time(:millisecond)
          k = RateLimiter.acquire("GET:/channels/700/test")
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
      key1 = RateLimiter.acquire("GET:/channels/800/test")

      start = System.monotonic_time(:millisecond)
      key2 = RateLimiter.acquire("GET:/channels/900/test")
      elapsed = System.monotonic_time(:millisecond) - start

      assert elapsed < 50

      RateLimiter.release(key1)
      RateLimiter.release(key2)
    end

    test "FIFO ordering is preserved" do
      key = RateLimiter.acquire("GET:/channels/1000/test")
      order = :ets.new(:order, [:set, :public])

      t1 =
        Task.async(fn ->
          k = RateLimiter.acquire("GET:/channels/1000/test")
          :ets.insert(order, {:t1, System.monotonic_time(:millisecond)})
          # hold it briefly so t2's acquire time is distinguishable
          Process.sleep(10)
          RateLimiter.release(k)
        end)

      # small delay so t1 queues before t2
      Process.sleep(20)

      t2 =
        Task.async(fn ->
          k = RateLimiter.acquire("GET:/channels/1000/test")
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

    test "lock is released when owner process dies" do
      {pid, ref} =
        spawn_monitor(fn ->
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
      key = RateLimiter.acquire("GET:/channels/1100/test")
      elapsed = System.monotonic_time(:millisecond) - start

      assert elapsed < 100
      RateLimiter.release(key)
    end

    test "dead waiter is skipped, next live waiter gets the lock" do
      key = RateLimiter.acquire("GET:/channels/1200/test")

      # waiter 1 will die while waiting
      {pid1, ref1} =
        spawn_monitor(fn ->
          RateLimiter.acquire("GET:/channels/1200/test")
        end)

      Process.sleep(20)

      # waiter 2 is alive
      t2 =
        Task.async(fn ->
          k = RateLimiter.acquire("GET:/channels/1200/test")
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
end
