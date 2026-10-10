defmodule Lingo.Rest.ClientTest do
  use ExUnit.Case, async: true

  alias Lingo.Rest.Client

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

  # answers every request with `response` and reports what was sent
  defp capture(response \\ {:ok, %{status: 200, headers: [], body: ""}}) do
    test_pid = self()

    Lingo.Instance.put(Lingo.Instance.current(), :http_request, fn method, url, headers, body ->
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

      assert {:error, %Lingo.Error{reason: :rate_limited, retry_after: 10}} =
               Client.request(:get, "/channels/100/messages")

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

    test "sends keyword list bodies as JSON objects, and lists of maps as arrays" do
      capture()

      assert :ok = Client.request(:patch, "/guilds/302", json: [name: "lingo"])
      assert_received {:sent, :patch, _url, _headers, {"application/json", body}}
      assert JSON.decode!(IO.iodata_to_binary(body)) == %{"name" => "lingo"}

      assert :ok = Client.request(:patch, "/guilds/302/roles", json: [%{id: "1", position: 2}])
      assert_received {:sent, :patch, _url, _headers, {"application/json", body}}
      assert JSON.decode!(IO.iodata_to_binary(body)) == [%{"id" => "1", "position" => 2}]
    end

    test "sends multipart bodies" do
      capture()

      multipart = Lingo.Rest.Body.multipart(%{content: "hi"}, [{"a.txt", "file contents"}])
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

      assert {:error, %Lingo.Error{reason: :api, status: 404, code: 10013}} =
               Client.request(:get, "/users/304")
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

      assert {:error, %Lingo.Error{reason: :rate_limited, retry_after: _}} =
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

  test "requests go to the configured REST proxy", %{bot: bot} do
    capture()
    Lingo.Instance.put(bot, :rest_base_url, "http://proxy.internal:8080/api/v10")

    Client.request(:get, "/users/@me")
    assert_received {:sent, :get, "http://proxy.internal:8080/api/v10/users/@me", _, _}
  end
end
