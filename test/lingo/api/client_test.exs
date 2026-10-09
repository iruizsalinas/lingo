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

    previous =
      for key <- [:http_request, :max_wait, :bot_module], do: {key, Lingo.Config.get(key)}

    Lingo.Config.put(:bot_module, nil)
    Lingo.Config.put(:max_wait, nil)

    on_exit(fn -> Enum.each(previous, fn {key, value} -> Lingo.Config.put(key, value) end) end)

    :ok
  end

  # every request is answered by `respond`, and reported back to the test process
  defp stub(respond) do
    test_pid = self()

    Lingo.Config.put(:http_request, fn method, url, _headers, _body ->
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

  # answers every request with `response` and reports what was sent
  defp capture(response \\ {:ok, %{status: 200, headers: [], body: ""}}) do
    test_pid = self()

    Lingo.Config.put(:http_request, fn method, url, headers, body ->
      send(test_pid, {:sent, method, url, headers, body})
      response
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

    test "a zero max_wait sends a single request" do
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

  describe "requests" do
    test "sends JSON bodies, query params and the audit log reason" do
      capture()

      assert :ok =
               Client.request(:patch, "/guilds/300",
                 json: %{name: "lingo"},
                 params: %{with_counts: true},
                 reason: "tidy up"
               )

      assert_received {:sent, :patch, url, headers, {"application/json", body}}
      assert url == "https://discord.com/api/v10/guilds/300?with_counts=true"
      assert {"x-audit-log-reason", "tidy%20up"} in headers
      assert {"authorization", "Bot " <> _} = List.keyfind(headers, "authorization", 0)
      assert JSON.decode!(IO.iodata_to_binary(body)) == %{"name" => "lingo"}
    end

    test "sends multipart bodies" do
      capture()

      multipart = Client.build_multipart(%{content: "hi"}, [{"a.txt", "file contents"}])
      assert :ok = Client.request(:post, "/channels/301/messages", multipart: multipart)

      assert_received {:sent, :post, _url, _headers,
                       {"multipart/form-data; boundary=" <> _, body}}

      body = IO.iodata_to_binary(body)
      assert body =~ ~s(name="files[0]"; filename="a.txt")
      assert body =~ "file contents"
    end

    test "sends no body when there is nothing to send" do
      capture()

      assert :ok = Client.request(:post, "/channels/302/typing")
      assert_received {:sent, :post, "https://discord.com/api/v10/channels/302/typing", _, nil}
    end

    test "decodes JSON responses and leaves other bodies alone" do
      capture(
        {:ok,
         %{status: 200, headers: [{"Content-Type", "application/json"}], body: ~s({"id":"1"})}}
      )

      assert {:ok, %{"id" => "1"}} = Client.request(:get, "/users/303")

      csv = "user_id\n1"
      capture({:ok, %{status: 200, headers: [{"content-type", "text/csv"}], body: csv}})
      assert {:ok, ^csv} = Client.request(:get, "/invites/abc/target-users")
    end

    test "returns error statuses with the decoded body" do
      body = ~s({"code":10013,"message":"Unknown User"})
      capture({:ok, %{status: 404, headers: [{"content-type", "application/json"}], body: body}})

      assert {:error, {404, %{"code" => 10013}}} = Client.request(:get, "/users/304")
    end
  end

  test "Lingo.with_max_wait/2 delegates to the client" do
    assert Lingo.with_max_wait(10, fn -> Process.get(:lingo_max_wait) end) == 10
  end

  describe "query params" do
    test "options Lingo doesn't know about still reach Discord" do
      capture({:ok, %{status: 200, headers: [{"content-type", "application/json"}], body: "[]"}})

      assert {:ok, []} = Lingo.Api.Member.list("123456789012", limit: 5, some_new_param: true)

      assert_receive {:sent, :get, url, _, _}
      query = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      assert query == %{"limit" => "5", "some_new_param" => "true"}
    end
  end

  describe "webhook buckets" do
    test "different webhook tokens do not share a rate limit bucket" do
      stub(fn ->
        {200,
         [
           {"x-ratelimit-bucket", "webhookhash"},
           {"x-ratelimit-remaining", "0"},
           {"x-ratelimit-reset-after", "30"},
           {"x-ratelimit-limit", "5"}
         ], %{"id" => "1"}}
      end)

      assert {:ok, _} = Client.request(:post, "/webhooks/111111111111/token_a", json: %{})

      # token_a is exhausted, token_b must still go through right away
      assert {:ok, _} =
               Lingo.with_max_wait(100, fn ->
                 Client.request(:post, "/webhooks/111111111111/token_b", json: %{})
               end)

      assert {:error, {:rate_limited, _}} =
               Lingo.with_max_wait(100, fn ->
                 Client.request(:post, "/webhooks/111111111111/token_a", json: %{})
               end)
    end

    test "different webhook ids do not share a rate limit bucket" do
      stub(fn ->
        {200, [{"x-ratelimit-remaining", "0"}, {"x-ratelimit-reset-after", "30"}], %{"id" => "1"}}
      end)

      assert {:ok, _} = Client.request(:get, "/webhooks/111111111111")

      assert {:ok, _} =
               Lingo.with_max_wait(100, fn -> Client.request(:get, "/webhooks/222222222222") end)
    end
  end
end
