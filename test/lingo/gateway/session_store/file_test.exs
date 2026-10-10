defmodule Lingo.Gateway.SessionStore.FileTest do
  use ExUnit.Case, async: true

  alias Lingo.Gateway.SessionStore.File, as: FileStore

  defp session,
    do: %{shard_id: 0, shard_count: 2, session_id: "s0", resume_gateway_url: "wss://r", seq: 5}

  @tag :tmp_dir
  test "the file store round trips, and a missing file holds nothing", %{tmp_dir: dir} do
    opts = [path: Path.join(dir, "sessions")]

    assert FileStore.load(:bot, opts) == []
    assert FileStore.save(:bot, [session()], opts) == :ok
    assert FileStore.load(:bot, opts) == [session()]

    File.write!(opts[:path], "garbage")
    assert FileStore.load(:bot, opts) == []
  end
end
