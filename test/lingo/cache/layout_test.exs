defmodule Lingo.Cache.LayoutTest do
  use ExUnit.Case, async: true
  alias Lingo.Cache
  alias Lingo.Cache.{Store, Tables}
  alias Lingo.Type.{Channel, Message, User}

  test "omitted cache allocates no resource tables and preserves bot identity" do
    Lingo.TestBot.start(start: [:cache], user_id: "me")
    Store.put_user(%User{id: "me"})
    Store.put_user(%User{id: "other"})
    Store.put_member("g", %Lingo.Type.Member{user: %User{id: "me"}})
    Store.put_member("g", %Lingo.Type.Member{user: %User{id: "other"}})
    Store.put_message(%Message{id: "m", channel_id: "c"})
    Store.put_current_user(%User{id: "me"})
    assert Cache.User.get_current().id == "me"
    assert Cache.User.get("me") == nil
    assert Cache.Member.get("g", "me") == nil
    assert Cache.User.get("other") == nil
    assert Cache.Member.get("g", "other") == nil

    for resource <- Lingo.Cache.Policy.resources() do
      assert Tables.resource(resource) == nil
      assert Cache.stats()[resource].memory_bytes == 0
    end
  end

  test "global and local storage options configure the actual ETS tables" do
    Lingo.TestBot.start(
      start: [:cache],
      cache: [
        compact: false,
        compressed: true,
        guilds: true,
        channels: true,
        roles: [compressed: false],
        messages: [compact: true]
      ]
    )

    assert :ets.info(Tables.table(:guilds), :compressed)
    refute :ets.info(Tables.table(:roles), :compressed)
    Store.put_channel(%Channel{id: "c"})
    Store.put_message(%Message{id: "m", channel_id: "c"})
    assert [{"c", channel}] = :ets.lookup(Tables.table(:channels), "c")
    assert channel === %Channel{id: "c"}
    assert [{_, message}] = :ets.lookup(Tables.table(:messages), {"c", "m"})
    refute Map.has_key?(message, :pinned)
    assert Cache.Message.get("c", "m") === %Message{id: "m", channel_id: "c"}
    assert Tables.resource(:presences) == nil
  end

  test "default message policy has only scoped eviction records and no expiration index" do
    Lingo.TestBot.start(start: [:cache], cache: [messages: true])
    Store.put_message(%Message{id: "m", channel_id: "c"})
    state = Tables.resource(:messages)
    assert state.expiry == nil
    assert :ets.info(state.order, :size) == 1
    assert :ets.info(state.order, :read_concurrency) == false
    assert :ets.info(state.order, :protection) == :private
    assert :ets.info(state.meta, :read_concurrency) == false
    assert :ets.info(state.table, :protection) == :protected
    assert Cache.stats().messages.entries == 1
  end

  test "global-only limits do not allocate scoped records or per-scope counters" do
    Lingo.TestBot.start(
      start: [:cache],
      cache: [only: [:messages], messages: [max_entries: 1, max_entries_per_channel: :infinity]]
    )

    Store.put_message(%Message{id: "a", channel_id: "c"})
    Store.put_message(%Message{id: "b", channel_id: "d"})
    state = Tables.resource(:messages)
    assert :ets.info(state.order, :size) == 1
    assert :sys.get_state(Lingo.Instance.process_name(Tables)).messages.counts == %{}
    assert Cache.Message.get("c", "a") == nil
    assert Cache.Message.get("d", "b").id == "b"
  end

  test "TTL-only and self-only policies allocate no eviction index" do
    Lingo.TestBot.start(
      start: [:cache],
      user_id: "me",
      cache: [only: [:users, :channels], users: :self, channels: [ttl: 10_000]]
    )

    Store.put_user(%User{id: "me"})
    Store.put_channel(%Channel{id: "c"})
    assert Tables.resource(:users).order == nil
    assert Tables.resource(:users).expiry == nil
    assert Tables.resource(:channels).order == nil
    assert :ets.info(Tables.resource(:channels).expiry, :size) == 1
    assert Cache.stats().users.kept == 1
    Cache.clear()
    assert Cache.stats().users.entries == 0
    assert :ets.info(Tables.resource(:channels).expiry, :size) == 0
  end

  test "unlimited caches use a single data table, while compression applies only to payloads" do
    Lingo.TestBot.start(
      start: [:cache],
      cache: [
        only: [:users, :messages],
        users: [compressed: true, filter: :all, keep: :none],
        messages: [compressed: true, ttl: 10_000]
      ]
    )

    refute Map.has_key?(Tables.resource(:users), :meta)
    Store.put_message(%Message{id: "m", channel_id: "c"})
    state = Tables.resource(:messages)
    assert :ets.info(state.table, :compressed)
    refute :ets.info(state.order, :compressed)
    refute :ets.info(state.expiry, :compressed)
  end

  test "scoped limits handle channels without a guild ID" do
    Lingo.TestBot.start(
      start: [:cache],
      cache: [only: [:channels], channels: [max_entries_per_guild: 1]]
    )

    Store.put_channel(%Channel{id: "a"})
    Store.put_channel(%Channel{id: "b"})
    assert Cache.Channel.get("a") == nil
    assert Cache.Channel.get("b").guild_id == nil
    Store.delete_channel("b")
    assert Cache.stats().channels.entries == 0
  end
end
