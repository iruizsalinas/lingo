defmodule Lingo.Bot.CooldownsTest do
  use ExUnit.Case, async: true

  alias Lingo.Bot.Cooldowns
  alias Lingo.Instance

  test "an expired window reopens when a dynamic cooldown changes its duration" do
    bot = Lingo.TestBot.start(start: [:cooldowns])
    table = Instance.process_name(bot, Cooldowns)
    key = {:chat_input, "dynamic", :user, "user"}

    for {previous, next} <- [{1_000, 60_000}, {60_000, 1_000}] do
      # Expiry is fixed without sleeping or waiting for the periodic sweep.
      start = System.monotonic_time(:millisecond) - previous - 1
      :ets.insert(table, {key, 1, start, previous})

      assert :ok = Cooldowns.hit(bot, key, {1, next, :user})
      assert [{^key, 1, reopened, ^next}] = :ets.lookup(table, key)
      assert reopened > start
      assert {:wait, remaining} = Cooldowns.hit(bot, key, {1, next, :user})
      assert remaining > 0 and remaining <= next
    end
  end

  test "changing duration preserves a window that has not expired" do
    bot = Lingo.TestBot.start(start: [:cooldowns])
    table = Instance.process_name(bot, Cooldowns)
    key = {:chat_input, "dynamic", :user, "user"}
    assert :ok = Cooldowns.hit(bot, key, {1, 60_000, :user})
    assert {:wait, remaining} = Cooldowns.hit(bot, key, {1, 1_000, :user})
    assert remaining > 50_000
    assert [{^key, _count, _start, 60_000}] = :ets.lookup(table, key)
  end
end
