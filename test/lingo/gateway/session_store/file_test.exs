defmodule Lingo.Gateway.SessionStore.FileTest do
  use ExUnit.Case, async: true

  alias Lingo.Gateway.SessionStore.File, as: FileStore

  defp session(opts \\ []) do
    Map.merge(
      %{shard_id: 0, shard_count: 2, session_id: "s0", resume_gateway_url: "wss://r", seq: 5},
      Map.new(opts)
    )
  end

  @tag :tmp_dir
  test "saves and deletes one shard at a time", %{tmp_dir: dir} do
    opts = [path: Path.join(dir, "sessions")]

    assert FileStore.load(:bot, opts) == []
    assert FileStore.save(:bot, session(), opts) == :ok
    assert FileStore.save(:bot, session(shard_id: 1, session_id: "s1"), opts) == :ok
    # replaces shard 0's session
    assert FileStore.save(:bot, session(seq: 9), opts) == :ok

    assert opts |> then(&FileStore.load(:bot, &1)) |> Enum.sort_by(& &1.shard_id) ==
             [session(seq: 9), session(shard_id: 1, session_id: "s1")]

    assert FileStore.delete(:bot, 0, 2, opts) == :ok
    assert FileStore.delete(:bot, 0, 2, opts) == :ok
    assert FileStore.load(:bot, opts) == [session(shard_id: 1, session_id: "s1")]
  end

  @tag :tmp_dir
  test "a missing or unreadable file holds nothing", %{tmp_dir: dir} do
    opts = [path: Path.join(dir, "sessions")]

    File.write!(opts[:path], "garbage")
    assert FileStore.load(:bot, opts) == []

    assert FileStore.save(:bot, session(), opts) == :ok
    assert FileStore.load(:bot, opts) == [session()]
  end
end
