defmodule Lingo.Rest.DeadlineTest do
  use ExUnit.Case, async: true

  alias Lingo.Rest.{Client, Deadline, RateLimiter}

  setup do
    %{bot: Lingo.TestBot.start(start: [:rate_limiter])}
  end

  # every request is answered by `respond`, and reported back to the test process
  defp stub(respond) do
    test_pid = self()

    Lingo.Instance.put(Lingo.Instance.current(), :http_request, fn method, url, _headers, _body ->
      send(test_pid, {:request, method, URI.parse(url).path})
      {status, headers, body} = respond.()

      {:ok,
       %{
         status: status,
         headers: [{"content-type", "application/json"} | headers],
         body: JSON.encode!(body)
       }}
    end)
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

  describe "max_wait" do
    test "an expired deadline permits requests that need no rate limit wait" do
      deadline = System.system_time(:millisecond) - 1_000

      refute Deadline.past?(0, deadline)
      assert Deadline.past?(1, deadline)
    end

    test "returns instead of sleeping through a long retry_after" do
      stub(fn -> rate_limited(30) end)

      start = System.monotonic_time(:millisecond)

      assert {:error, %Lingo.Error{reason: :rate_limited, retry_after: 30_000}} =
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

      Lingo.Rest.Buckets.update("get:/channels/202", [
        {"x-ratelimit-remaining", "0"},
        {"x-ratelimit-reset-after", "60"}
      ])

      assert {:error, %Lingo.Error{reason: :rate_limited, retry_after: ms}} =
               Client.with_max_wait(1_000, fn -> Client.request(:get, "/channels/202") end)

      assert ms > 59_000
      assert request_count() == 0
    end

    test "does not send a request during a global pause longer than the budget" do
      stub(fn -> {200, [], %{}} end)
      Lingo.Rest.GlobalLimit.pause(60_000)

      assert {:error, %Lingo.Error{reason: :rate_limited, retry_after: _}} =
               Client.with_max_wait(1_000, fn -> Client.request(:get, "/channels/203") end)

      assert request_count() == 0
    end

    test "gives up while queued behind a slow request in the same bucket" do
      {:ok, key} = RateLimiter.acquire("get:/channels/204")
      stub(fn -> {200, [], %{}} end)

      start = System.monotonic_time(:millisecond)

      assert {:error, %Lingo.Error{reason: :rate_limited, retry_after: _}} =
               Client.with_max_wait(150, fn -> Client.request(:get, "/channels/204") end)

      elapsed = System.monotonic_time(:millisecond) - start
      assert elapsed >= 150 and elapsed < 500

      RateLimiter.release(key)
    end

    test "uses the configured default and restores the previous value" do
      stub(fn -> rate_limited(30) end)
      Lingo.Instance.put(Lingo.Instance.current(), :max_wait, 1_000)

      assert {:error, %Lingo.Error{reason: :rate_limited, retry_after: _}} =
               Client.request(:get, "/channels/205/messages")

      Client.with_max_wait(5, fn -> :ok end)
      assert Process.get(:lingo_max_wait) == nil
    end
  end
end
