defmodule Lingo.Rest.BucketsTest do
  use ExUnit.Case, async: true

  setup do
    %{bot: Lingo.TestBot.start(start: [:rate_limiter])}
  end

  defp table(key), do: Map.fetch!(Lingo.Instance.get(:rate_limiter), key)
  defp limiter, do: Process.whereis(Lingo.Instance.process_name(Lingo.Rest.RateLimiter))

  describe "update/2 with list headers" do
    test "stores rate limit state and maps route to bucket" do
      headers = [
        {"x-ratelimit-bucket", "abc123"},
        {"x-ratelimit-remaining", "4"},
        {"x-ratelimit-reset-after", "1.5"},
        {"x-ratelimit-limit", "5"}
      ]

      Lingo.Rest.Buckets.update("GET:/channels/123/test", headers)

      # route should be mapped to bucket_key "abc123:123"
      [{_, bucket_key}] = :ets.lookup(table(:bucket_map), "GET:/channels/123/test")
      assert bucket_key == "abc123:123"

      [{^bucket_key, remaining, reset_at, limit}] = :ets.lookup(table(:buckets), bucket_key)
      assert remaining == 4
      assert limit == 5
      assert reset_at > System.system_time(:millisecond)
    end

    test "ignores headers without rate limit info" do
      Lingo.Rest.Buckets.update("GET:/no/info", [{"content-type", "application/json"}])
      assert :ets.lookup(table(:bucket_map), "GET:/no/info") == []
    end

    test "parses headers case-insensitively" do
      headers = [
        {"X-RateLimit-Bucket", "case123"},
        {"X-RateLimit-Remaining", "2"},
        {"X-RateLimit-Reset-After", "1.0"},
        {"X-RateLimit-Limit", "5"}
      ]

      Lingo.Rest.Buckets.update("GET:/channels/123/case", headers)

      [{_, bucket_key}] = :ets.lookup(table(:bucket_map), "GET:/channels/123/case")
      assert bucket_key == "case123:123"
    end
  end

  describe "update/2 with map headers" do
    test "parses map-style headers" do
      headers = %{
        "x-ratelimit-bucket" => ["def456"],
        "x-ratelimit-remaining" => ["0"],
        "x-ratelimit-reset-after" => ["2.0"],
        "x-ratelimit-limit" => ["5"]
      }

      Lingo.Rest.Buckets.update("GET:/guilds/789/test", headers)

      [{_, bucket_key}] = :ets.lookup(table(:bucket_map), "GET:/guilds/789/test")
      assert bucket_key == "def456:789"

      [{^bucket_key, remaining, _reset_at, limit}] = :ets.lookup(table(:buckets), bucket_key)
      assert remaining == 0
      assert limit == 5
    end

    test "parses map-style headers case-insensitively" do
      headers = %{
        "X-RateLimit-Bucket" => ["mapcase"],
        "X-RateLimit-Remaining" => ["1"],
        "X-RateLimit-Reset-After" => ["1.0"],
        "X-RateLimit-Limit" => ["5"]
      }

      Lingo.Rest.Buckets.update("GET:/guilds/456/case", headers)

      [{_, bucket_key}] = :ets.lookup(table(:bucket_map), "GET:/guilds/456/case")
      assert bucket_key == "mapcase:456"
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

      Lingo.Rest.Buckets.update("GET:/channels/100/messages/:id", h1)
      Lingo.Rest.Buckets.update("GET:/channels/100/pins", h2)

      # both map to the same bucket key
      [{_, bk1}] = :ets.lookup(table(:bucket_map), "GET:/channels/100/messages/:id")
      [{_, bk2}] = :ets.lookup(table(:bucket_map), "GET:/channels/100/pins")
      assert bk1 == bk2
      assert bk1 == "shared_hash:100"

      # the second update overwrote remaining, so wait should see remaining=1
      [{_, remaining, _, _}] = :ets.lookup(table(:buckets), bk1)
      assert remaining == 1
    end
  end

  describe "cleanup" do
    test "deletes expired buckets without deleting fresh buckets" do
      now = System.system_time(:millisecond)

      :ets.insert(table(:buckets), {"expired", 0, now - 31_000, 1})
      :ets.insert(table(:buckets), {"fresh", 0, now + 1_000, 1})

      send(limiter(), :cleanup)
      Process.sleep(20)

      assert :ets.lookup(table(:buckets), "expired") == []
      assert [{_, 0, _, 1}] = :ets.lookup(table(:buckets), "fresh")
    end
  end

  describe "wait/1" do
    test "passes immediately when no bucket exists" do
      assert Lingo.Rest.Buckets.wait("GET:/unknown/route") == :ok
    end

    test "returns immediately when remaining > 0" do
      headers = [
        {"x-ratelimit-bucket", "b"},
        {"x-ratelimit-remaining", "10"},
        {"x-ratelimit-reset-after", "5.0"},
        {"x-ratelimit-limit", "10"}
      ]

      Lingo.Rest.Buckets.update("GET:/channels/200/test", headers)

      start = System.monotonic_time(:millisecond)
      assert Lingo.Rest.Buckets.wait("GET:/channels/200/test") == :ok
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

      Lingo.Rest.Buckets.update("GET:/channels/300/test", headers)

      start = System.monotonic_time(:millisecond)
      assert Lingo.Rest.Buckets.wait("GET:/channels/300/test") == :ok
      elapsed = System.monotonic_time(:millisecond) - start

      assert elapsed >= 80
    end
  end

  describe "wait_global/0" do
    test "passes immediately when not paused" do
      start = System.monotonic_time(:millisecond)
      assert Lingo.Rest.GlobalLimit.wait() == :ok
      assert System.monotonic_time(:millisecond) - start < 50
    end

    test "blocks until pause expires" do
      Lingo.Rest.GlobalLimit.pause(100)

      start = System.monotonic_time(:millisecond)
      assert Lingo.Rest.GlobalLimit.wait() == :ok
      elapsed = System.monotonic_time(:millisecond) - start

      assert elapsed >= 80
    end

    test "pause is cleared after wait" do
      Lingo.Rest.GlobalLimit.pause(50)
      Lingo.Rest.GlobalLimit.wait()

      start = System.monotonic_time(:millisecond)
      assert Lingo.Rest.GlobalLimit.wait() == :ok
      assert System.monotonic_time(:millisecond) - start < 50
    end

    test "shorter later pause does not shorten an active global pause" do
      Lingo.Rest.GlobalLimit.pause(180)
      Process.sleep(40)
      Lingo.Rest.GlobalLimit.pause(20)

      start = System.monotonic_time(:millisecond)
      assert Lingo.Rest.GlobalLimit.wait() == :ok
      elapsed = System.monotonic_time(:millisecond) - start

      assert elapsed >= 120
    end

    test "wait observes a global pause extended while waiting" do
      Lingo.Rest.GlobalLimit.pause(70)

      task =
        Task.async(fn ->
          start = System.monotonic_time(:millisecond)
          Lingo.Rest.GlobalLimit.wait()
          System.monotonic_time(:millisecond) - start
        end)

      Process.sleep(30)
      Lingo.Rest.GlobalLimit.pause(150)

      assert Task.await(task, 1_000) >= 150
    end
  end

  describe "deadlines" do
    defp exhaust(route_key, reset_after) do
      Lingo.Rest.Buckets.update(route_key, [
        {"x-ratelimit-bucket", "deadline_#{:erlang.unique_integer([:positive])}"},
        {"x-ratelimit-remaining", "0"},
        {"x-ratelimit-reset-after", reset_after},
        {"x-ratelimit-limit", "5"}
      ])
    end

    test "wait/2 returns the remaining time instead of sleeping past the deadline" do
      exhaust("GET:/channels/1300/test", "5.0")
      deadline = System.system_time(:millisecond) + 100

      start = System.monotonic_time(:millisecond)

      assert {:error, {:rate_limited, ms}} =
               Lingo.Rest.Buckets.wait("GET:/channels/1300/test", deadline)

      assert System.monotonic_time(:millisecond) - start < 50
      assert ms > 4_000 and ms <= 5_000
    end

    test "wait/2 sleeps when the reset is within the deadline" do
      exhaust("GET:/channels/1400/test", "0.1")
      deadline = System.system_time(:millisecond) + 1_000

      assert Lingo.Rest.Buckets.wait("GET:/channels/1400/test", deadline) == :ok
    end

    test "wait_global/1 returns the remaining pause past the deadline" do
      Lingo.Rest.GlobalLimit.pause(5_000)
      deadline = System.system_time(:millisecond) + 100

      assert {:error, {:rate_limited, ms}} = Lingo.Rest.GlobalLimit.wait(deadline)
      assert ms > 4_000
    end

    test "wait_time/1 reports the longer of the bucket and global waits" do
      assert Lingo.Rest.Buckets.wait_time("GET:/channels/1500/test") == 0

      exhaust("GET:/channels/1500/test", "1.0")
      assert Lingo.Rest.Buckets.wait_time("GET:/channels/1500/test") in 900..1_000

      Lingo.Rest.GlobalLimit.pause(3_000)
      assert Lingo.Rest.Buckets.wait_time("GET:/channels/1500/test") in 2_900..3_000
    end
  end
end
