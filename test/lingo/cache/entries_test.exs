defmodule Lingo.Cache.EntriesTest do
  use ExUnit.Case, async: true
  alias Lingo.Cache
  alias Lingo.Cache.{Store, Tables}
  alias Lingo.Type.{Member, Message, User}

  defp start(policy), do: Lingo.TestBot.start(start: [:cache], cache: policy, user_id: "me")
  defp message(id, channel \\ "c"), do: %Message{id: id, channel_id: channel, guild_id: "g"}

  test "global and per-channel limits evict oldest writes independently" do
    start(only: [:messages], messages: [max_entries: 3, max_entries_per_channel: 2])
    for id <- ["1", "2", "3"], do: Store.put_message(message(id))
    assert Cache.Message.get("c", "1") == nil
    Store.put_message(message("4", "d"))
    Store.put_message(message("5", "d"))
    assert Cache.Message.get("c", "2") == nil
    assert Cache.Message.get("c", "3").id == "3"
    assert Cache.stats().messages.entries == 3
  end

  test "rewriting an entry refreshes eviction order without inflating counts" do
    start(only: [:messages], messages: [max_entries_per_channel: 2])
    Store.put_message(message("1"))
    Store.put_message(message("2"))
    Store.put_message(%{message("1") | content: "updated"})
    Store.put_message(message("3"))
    assert Cache.Message.get("c", "2") == nil
    assert Cache.Message.get("c", "1").content == "updated"
    assert Cache.stats().messages.entries == 2
  end

  test "members are bounded per guild, with an independent global budget" do
    start(
      only: [:members],
      members: [max_entries: 3, max_entries_per_guild: 2, filter: :all, keep: :none]
    )

    for {guild, id} <- [{"a", "1"}, {"a", "2"}, {"a", "3"}, {"b", "4"}, {"b", "5"}] do
      Store.put_member(guild, %Member{guild_id: guild, user: %User{id: id}})
    end

    assert Cache.Member.get("a", "1") == nil
    assert Cache.Member.get("a", "2") == nil
    assert Cache.Member.get("a", "3").user.id == "3"
    assert Cache.stats().members.entries == 3
  end

  test "kept entries override filter, capacity and TTL but explicit removal wins" do
    start(only: [:users], users: [max_entries: 0, ttl: 1, filter: :none, keep: :self])
    Store.put_user(%User{id: "me"})
    Store.put_user(%User{id: "other"})
    Process.sleep(5)
    assert Cache.User.get("me").id == "me"
    assert Cache.User.get("other") == nil
    assert %{entries: 1, kept: 1, overflow: %{global: 1}} = Cache.stats().users
    Cache.clear(:users)
    assert Cache.User.get("me") == nil
    assert Cache.stats().users.entries == 0
  end

  test "all kept entries may overflow; ordinary entries cannot increase overflow" do
    start(
      only: [:messages],
      messages: [
        max_entries: 1,
        max_entries_per_channel: 1,
        keep: fn msg, _ -> msg.content == "keep" end
      ]
    )

    Store.put_message(%{message("1") | content: "keep"})
    Store.put_message(%{message("2") | content: "keep"})
    Store.put_message(message("3"))
    assert Cache.Message.get("c", "3") == nil
    assert %{entries: 2, kept: 2, overflow: %{global: 1, scoped: 1}} = Cache.stats().messages
    Store.delete_message("c", "1")
    assert Cache.stats().messages.entries == 1
    Store.put_message(%{message("2") | content: "ordinary"})
    Store.put_message(message("4"))
    assert Cache.Message.get("c", "2") == nil
    assert Cache.stats().messages.kept == 0
  end

  test "TTL hides expired entries immediately, including list reads; cleanup is bounded" do
    start(only: [:guilds], guilds: [ttl: 10])
    Store.put_guild(%Lingo.Type.Guild{id: "g"})
    Process.sleep(20)
    assert Cache.Guild.get("g") == nil
    assert Cache.Guild.list() == []
    send(Lingo.Instance.process_name(Lingo.Cache.Tables), :sweep)
    assert Cache.stats().guilds.entries == 0
  end

  test "TTL is refreshed by writes and not by reads" do
    start(only: [:users], users: [ttl: 100, filter: :all, keep: :none])
    Store.put_user(%User{id: "u", username: "first"})
    Process.sleep(60)
    Store.put_user(%User{id: "u", username: "second"})
    Process.sleep(60)
    assert Cache.User.get("u").username == "second"
    Process.sleep(60)
    assert Cache.User.get("u") == nil
  end

  test "concurrent writes enforce limits and deletion keeps indexes consistent" do
    start(only: [:messages], messages: [max_entries: 20, max_entries_per_channel: 10])

    1..100
    |> Task.async_stream(fn id ->
      Store.put_message(message(Integer.to_string(id), "#{rem(id, 3)}"))
    end)
    |> Stream.run()

    assert Cache.stats().messages.entries == 20
    Store.delete_guild("g")
    assert Cache.stats().messages.entries == 0
    Store.put_message(message("next"))
    assert Cache.stats().messages.entries == 1
    assert Cache.Message.get("c", "next").id == "next"
    assert :ets.info(Tables.resource(:messages).meta, :size) == 1
  end
end
