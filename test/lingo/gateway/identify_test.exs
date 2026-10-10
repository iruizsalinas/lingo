defmodule Lingo.Gateway.IdentifyTest do
  use ExUnit.Case, async: true

  alias Lingo.Gateway.Identify

  defp start(plan) do
    bot = Lingo.TestBot.start()
    pid = start_supervised!({Identify, bot: bot, plan: plan})
    {bot, pid}
  end

  defp plan(opts),
    do: Map.merge(%{max_concurrency: 1, remaining: 1_000, reset_after: 60_000}, Map.new(opts))

  test "identify slots are spaced per max_concurrency bucket" do
    start(plan(max_concurrency: 2))

    assert Identify.reserve(0) == {:ok, 0}
    assert Identify.reserve(1) == {:ok, 0}

    # shard 2 shares bucket 0 with shard 0
    assert {:ok, wait} = Identify.reserve(2)
    assert wait > 5_000
  end

  test "waits for the daily limit to reset instead of going over it" do
    start(plan(remaining: 1, reset_after: 60_000))

    assert Identify.reserve(0) == {:ok, 0}
    assert {:wait, wait} = Identify.reserve(1)
    assert wait > 55_000 and wait <= 60_000
  end

  test "asks Discord again once the limit is due to reset" do
    test_pid = self()

    http = fn :get, url, _headers, _body ->
      send(test_pid, {:fetched, URI.parse(url).path})
      limit = %{"remaining" => 5, "reset_after" => 1_000, "max_concurrency" => 1}
      body = %{"url" => "wss://gateway", "shards" => 1, "session_start_limit" => limit}

      {:ok,
       %{status: 200, headers: [{"content-type", "application/json"}], body: JSON.encode!(body)}}
    end

    bot = Lingo.TestBot.start(http_request: http, start: [:rate_limiter])
    start_supervised!({Identify, bot: bot, plan: plan(remaining: 0, reset_after: 0)})

    assert Identify.reserve(0) == {:ok, 0}
    assert_received {:fetched, "/api/v10/gateway/bot"}
  end

  test "another node's identifies go through the leader" do
    {bot, leader} = start(plan(max_concurrency: 1))

    # a second Identify for the same bot, as another node would start
    {:ok, follower} = Lingo.Instance.with_current(bot, fn -> Identify.init(bot: bot) end)
    assert follower.role == :follower
    assert follower.leader == leader

    assert {:reply, {:ok, 0}, _} = Identify.handle_call({:reserve, 0}, self(), follower)
    # the leader counted it: the next identify in that bucket waits
    assert {:ok, wait} = Identify.reserve(0)
    assert wait > 5_000
  end

  test "a follower takes over when the leader goes away, after a pause" do
    {bot, leader} = start(plan([]))
    {:ok, follower} = Lingo.Instance.with_current(bot, fn -> Identify.init(bot: bot) end)

    stop_supervised!(Identify)
    refute Process.alive?(leader)

    {:noreply, state} =
      Identify.handle_info({:DOWN, make_ref(), :process, leader, :shutdown}, follower)

    assert state.role == :leader
    assert state.paused_until > System.monotonic_time(:millisecond)
    :global.unregister_name(state.name)
  end
end
