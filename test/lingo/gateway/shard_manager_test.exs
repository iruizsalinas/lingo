defmodule Lingo.Gateway.ShardManagerTest do
  use ExUnit.Case, async: true

  alias Lingo.Gateway.ShardManager

  test "identify slots are spaced per max_concurrency bucket" do
    state = %ShardManager{max_concurrency: 2}

    {:reply, 0, state} = ShardManager.handle_call({:reserve_identify, 0}, self(), state)
    {:reply, 0, state} = ShardManager.handle_call({:reserve_identify, 1}, self(), state)
    {:reply, wait, _state} = ShardManager.handle_call({:reserve_identify, 2}, self(), state)

    # shard 2 shares bucket 0 with shard 0
    assert wait > 5_000
  end
end
