defmodule Lingo.Api.ClientTest do
  use ExUnit.Case

  alias Lingo.Api.{Client, RateLimiter}

  setup do
    if Process.whereis(RateLimiter) do
      for table <- [:lingo_rate_limits, :lingo_bucket_map, :lingo_global_rate_limit] do
        :ets.delete_all_objects(table)
      end
    else
      start_supervised!(RateLimiter)
    end

    previous = for key <- [:req_options, :max_wait, :bot_module], do: {key, Lingo.Config.get(key)}
    Lingo.Config.put(:bot_module, nil)
    Lingo.Config.put(:max_wait, nil)

    on_exit(fn -> Enum.each(previous, fn {key, value} -> Lingo.Config.put(key, value) end) end)

    :ok
  end

  # every request is answered by `respond`, and reported back to the test process
  defp stub(respond) do
    test_pid = self()

    adapter = fn request ->
      send(test_pid, {:request, request.method, request.url.path})
      {status, headers, body} = respond.()

      response =
        Req.Response.new(status: status, body: Jason.encode!(body))
        |> Req.Response.put_header("content-type", "application/json")

      response =
        Enum.reduce(headers, response, fn {k, v}, r -> Req.Response.put_header(r, k, v) end)

      {request, response}
    end

    Lingo.Config.put(:req_options, adapter: adapter)
  end

  defp rate_limited(retry_after, global \\ false) do
    {429, [{"retry-after", to_string(retry_after)}],
     %{
       "message" => "You are being rate limited.",
       "retry_after" => retry_after,
       "global" => global
     }}
  end

  defp request_count do
    receive do
      {:request, _, _} -> 1 + request_count()
    after
      0 -> 0
    end
  end

  describe "429 retries" do
    test "gives up after 5 rate limited retries" do
      stub(fn -> rate_limited(0.01) end)

      assert {:error, {:rate_limited, 10}} = Client.request(:get, "/channels/100/messages")
      assert request_count() == 6
    end

    test "succeeds when a retry gets through" do
      counter = :counters.new(1, [])

      stub(fn ->
        :counters.add(counter, 1, 1)
        if :counters.get(counter, 1) < 3, do: rate_limited(0.01), else: {200, [], %{"id" => "1"}}
      end)

      assert {:ok, %{"id" => "1"}} = Client.request(:get, "/channels/101/messages")
      assert request_count() == 3
    end

    test "Req does not retry 429s on its own" do
      stub(fn -> rate_limited(0.01) end)

      Client.with_max_wait(0, fn -> Client.request(:get, "/channels/102/messages") end)
      assert request_count() == 1
    end
  end

  describe "max_wait" do
    test "returns instead of sleeping through a long retry_after" do
      stub(fn -> rate_limited(30) end)

      start = System.monotonic_time(:millisecond)

      assert {:error, {:rate_limited, 30_000}} =
               Client.with_max_wait(1_000, fn ->
                 Client.request(:get, "/channels/200/messages")
               end)

      assert System.monotonic_time(:millisecond) - start < 500
      assert request_count() == 1
    end

    test "still waits for short rate limits within the budget" do
      counter = :counters.new(1, [])

      stub(fn ->
        :counters.add(counter, 1, 1)
        if :counters.get(counter, 1) == 1, do: rate_limited(0.05), else: {200, [], %{"id" => "1"}}
      end)

      assert {:ok, _} =
               Client.with_max_wait(1_000, fn ->
                 Client.request(:get, "/channels/201/messages")
               end)
    end

    test "does not send a request into a bucket that is known to be exhausted" do
      stub(fn -> {200, [], %{}} end)

      RateLimiter.update("get:/channels/202", [
        {"x-ratelimit-remaining", "0"},
        {"x-ratelimit-reset-after", "60"}
      ])

      assert {:error, {:rate_limited, ms}} =
               Client.with_max_wait(1_000, fn -> Client.request(:get, "/channels/202") end)

      assert ms > 59_000
      assert request_count() == 0
    end

    test "does not send a request during a global pause longer than the budget" do
      stub(fn -> {200, [], %{}} end)
      RateLimiter.pause_global(60_000)

      assert {:error, {:rate_limited, _}} =
               Client.with_max_wait(1_000, fn -> Client.request(:get, "/channels/203") end)

      assert request_count() == 0
    end

    test "gives up while queued behind a slow request in the same bucket" do
      {:ok, key} = RateLimiter.acquire("get:/channels/204")
      stub(fn -> {200, [], %{}} end)

      start = System.monotonic_time(:millisecond)

      assert {:error, {:rate_limited, _}} =
               Client.with_max_wait(150, fn -> Client.request(:get, "/channels/204") end)

      elapsed = System.monotonic_time(:millisecond) - start
      assert elapsed >= 150 and elapsed < 500

      RateLimiter.release(key)
    end

    test "uses the configured default and restores the previous value" do
      stub(fn -> rate_limited(30) end)
      Lingo.Config.put(:max_wait, 1_000)

      assert {:error, {:rate_limited, _}} = Client.request(:get, "/channels/205/messages")

      Client.with_max_wait(5, fn -> :ok end)
      assert Process.get(:lingo_max_wait) == nil
    end
  end

  test "Lingo.with_max_wait/2 delegates to the client" do
    assert Lingo.with_max_wait(10, fn -> Process.get(:lingo_max_wait) end) == 10
  end
end
