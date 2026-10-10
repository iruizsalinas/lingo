defmodule Lingo.Gateway.SessionsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Lingo.Gateway.Sessions

  defmodule Store do
    @behaviour Lingo.Gateway.SessionStore

    @impl true
    def load(_bot, opts), do: opts[:sessions]

    @impl true
    def save(bot, session, opts), do: send(opts[:test_pid], {:saved, bot, session})

    @impl true
    def delete(bot, shard_id, count, opts),
      do: send(opts[:test_pid], {:deleted, bot, shard_id, count})
  end

  defmodule BrokenStore do
    @behaviour Lingo.Gateway.SessionStore

    @impl true
    def load(_bot, _opts), do: raise("down")

    @impl true
    def save(_bot, _session, _opts), do: raise("down")

    @impl true
    def delete(_bot, _shard_id, _count, _opts), do: raise("down")
  end

  defp session(opts \\ []) do
    Map.merge(
      %{shard_id: 0, shard_count: 2, session_id: "s0", resume_gateway_url: "wss://r", seq: 5},
      Map.new(opts)
    )
  end

  defp store(opts \\ []), do: {Store, Keyword.merge([sessions: [], test_pid: self()], opts)}

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
    assert Sessions.delete(bot, 0, 1) == :ok
    assert Sessions.fetch(bot, 0, 1) == nil
    assert Sessions.list(bot) == []
  end

  test "loads valid sessions from the store and saves them on stop" do
    bot = Lingo.TestBot.start()
    sessions = [session(), session(shard_id: 5, shard_count: 2), %{shard_id: "bad"}]

    start_supervised!({Sessions, bot: bot, store: store(sessions: sessions)})

    assert Sessions.fetch(bot, 0, 2) == {"s0", "wss://r", 5}
    Sessions.seq(bot, 0, 2, 7)

    stop_supervised!(Sessions)
    assert_received {:saved, ^bot, %{shard_id: 0, seq: 7}}
  end

  test "each shard is saved when its session starts or resumes" do
    bot = Lingo.TestBot.start()
    start_supervised!({Sessions, bot: bot, store: store()})

    Sessions.put(bot, 1, 2, "s1", "wss://r", 0)
    assert_receive {:saved, ^bot, %{shard_id: 1, session_id: "s1", seq: 0}}

    Sessions.seq(bot, 1, 2, 40)
    refute_receive {:saved, _, _}, 50

    Sessions.save(bot, 1, 2)
    assert_receive {:saved, ^bot, %{shard_id: 1, seq: 40}}
  end

  test "a session that can't resume is deleted from the store" do
    bot = Lingo.TestBot.start()
    start_supervised!({Sessions, bot: bot, store: store(sessions: [session()])})

    Sessions.delete(bot, 0, 2)
    assert_receive {:deleted, ^bot, 0, 2}
    assert Sessions.fetch(bot, 0, 2) == nil
  end

  test "a node loads only the sessions of its own shards" do
    bot = Lingo.TestBot.start()
    sessions = [session(shard_id: 0), session(shard_id: 1, session_id: "s1")]
    start_supervised!({Sessions, bot: bot, ids: [1], store: store(sessions: sessions)})

    assert Sessions.fetch(bot, 0, 2) == nil
    assert Sessions.fetch(bot, 1, 2) == {"s1", "wss://r", 5}
  end

  test "on stop, sessions under another shard count are deleted, not saved" do
    bot = Lingo.TestBot.start()
    sessions = [session(shard_count: 2), session(shard_count: 3, session_id: "old")]
    start_supervised!({Sessions, bot: bot, store: store(sessions: sessions)})
    Lingo.Instance.put(bot, :shard_count, 2)

    stop_supervised!(Sessions)
    assert_received {:saved, ^bot, %{shard_count: 2}}
    assert_received {:deleted, ^bot, 0, 3}
    refute_received {:saved, ^bot, %{shard_count: 3}}
  end

  test "a store that raises is logged, and the bot carries on" do
    bot = Lingo.TestBot.start()

    log =
      capture_log(fn ->
        start_supervised!({Sessions, bot: bot, store: {BrokenStore, []}})
        # each cast is handled before the call after it returns
        Sessions.put(bot, 0, 1, "s", "wss://r", 1)
        :sys.get_state(Lingo.Instance.process_name(bot, Sessions))
        Sessions.delete(bot, 0, 1)
        :sys.get_state(Lingo.Instance.process_name(bot, Sessions))
        stop_supervised!(Sessions)
      end)

    assert log =~ "session store failed to load"
    assert log =~ "session store failed to save"
    assert log =~ "session store failed to delete"
  end

  test "warns when a store meets a cache" do
    bot = Lingo.TestBot.start()

    log =
      capture_log(fn ->
        start_supervised!({Sessions, bot: bot, cache?: true, store: store()})
      end)

    assert log =~ "cache starts without them"
  end
end
