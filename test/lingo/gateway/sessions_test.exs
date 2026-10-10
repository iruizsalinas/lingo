defmodule Lingo.Gateway.SessionsTest do
  use ExUnit.Case, async: true

  alias Lingo.Gateway.Sessions

  defmodule Store do
    @behaviour Lingo.Gateway.SessionStore

    @impl true
    def load(_bot, opts), do: opts[:sessions]

    @impl true
    def save(bot, sessions, opts), do: send(opts[:test_pid], {:saved, bot, sessions})
  end

  defp session(opts \\ []) do
    Map.merge(
      %{shard_id: 0, shard_count: 2, session_id: "s0", resume_gateway_url: "wss://r", seq: 5},
      Map.new(opts)
    )
  end

  test "keeps one session per shard id and count" do
    bot = Lingo.TestBot.start(start: [:sessions])

    Sessions.put(bot, 0, 2, "s0", "wss://r", 1)
    Sessions.seq(bot, 0, 2, 9)
    Sessions.put(bot, 0, 3, "other", "wss://r", 1)

    assert Sessions.fetch(bot, 0, 2) == {"s0", "wss://r", 9}
    assert Sessions.fetch(bot, 1, 2) == nil

    Sessions.delete(bot, 0, 3)
    assert Sessions.list(bot) == [session(seq: 9)]
  end

  test "without the process, nothing is kept and nothing fails" do
    bot = Lingo.TestBot.start()

    assert Sessions.put(bot, 0, 1, "s", "wss://r", 1) == :ok
    assert Sessions.seq(bot, 0, 1, 2) == :ok
    assert Sessions.fetch(bot, 0, 1) == nil
    assert Sessions.list(bot) == []
  end

  test "loads valid sessions from the store and saves them on stop" do
    bot = Lingo.TestBot.start()
    sessions = [session(), session(shard_id: 5, shard_count: 2), %{shard_id: "bad"}]

    start_supervised!({Sessions, bot: bot, store: {Store, sessions: sessions, test_pid: self()}})

    assert Sessions.fetch(bot, 0, 2) == {"s0", "wss://r", 5}
    Sessions.seq(bot, 0, 2, 7)

    stop_supervised!(Sessions)
    assert_received {:saved, ^bot, [%{shard_id: 0, seq: 7}]}
  end
end
