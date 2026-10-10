defmodule Lingo.Cache.StoreTest do
  use ExUnit.Case, async: true
  alias Lingo.Cache
  alias Lingo.Cache.{Store, Tables}
  alias Lingo.Type.{Channel, Guild, Member, Message, Presence, Role, User}

  test "member and presence users survive independent user eviction or disabling" do
    for users <- [false, [max_entries: 1, filter: :all, keep: :none]] do
      Lingo.TestBot.start(start: [:cache], cache: [users: users, members: true, presences: true])
      user = %User{id: "u", username: "alice", bot: true}
      Store.put_member("g", %Member{guild_id: "g", user: user})
      Store.put_presence("g", %Presence{guild_id: "g", user: user})
      Store.put_user(%User{id: "other"})
      assert Cache.get_user("u") == nil
      assert Cache.get_member("g", "u").user.username == "alice"
      assert Cache.get_presence("g", "u").user.username == "alice"
      Store.put_presence("g", %Presence{guild_id: "g", user: %User{id: "u"}, status: :idle})
      assert Cache.get_presence("g", "u").user.bot == true
    end
  end

  test "deletion cleans children with guild and channel caches disabled" do
    Lingo.TestBot.start(
      start: [:cache],
      cache: [guilds: false, channels: false, members: true, roles: true, messages: true]
    )

    Store.put_member("g", %Member{user: %User{id: "u"}})
    Store.put_role("g", %Role{id: "r"})
    Store.put_message(%Message{id: "m", channel_id: "c", guild_id: "g"})
    Store.delete_guild("g")
    assert Cache.get_member("g", "u") == nil
    assert Cache.get_role("g", "r") == nil
    assert Cache.get_message("c", "m") == nil
    Store.put_message(%Message{id: "m", channel_id: "c", guild_id: "g"})
    Store.delete_channel("c")
    assert Cache.get_message("c", "m") == nil
  end

  test "resource eviction and clearing do not cascade into other resources" do
    Lingo.TestBot.start(start: [:cache], cache: [channels: [max_entries: 1], messages: true])
    Store.put_channel(%Channel{id: "c", guild_id: "g"})
    Store.put_message(%Message{id: "m", channel_id: "c", guild_id: "g"})
    Store.put_channel(%Channel{id: "d", guild_id: "g"})
    assert Cache.get_channel("c") == nil
    assert Cache.get_message("c", "m").id == "m"
    Cache.clear(:guilds)
    assert Cache.get_message("c", "m").id == "m"
  end

  test "guild deletion also removes messages without a guild ID in known channels" do
    Lingo.TestBot.start(start: [:cache], cache: [channels: true, messages: true])
    Store.put_channel(%Channel{id: "c", guild_id: "g"})
    Store.put_message(%Message{id: "m", channel_id: "c"})
    Store.delete_guild("g")
    assert Cache.get_channel("c") == nil
    assert Cache.get_message("c", "m") == nil
  end

  test "disabled resources skip traversal and cache-only constructors" do
    Lingo.TestBot.start(start: [:cache], cache: false)
    assert Store.put_all(:channels, :not_enumerable, fn _ -> raise "visited" end) == :ok
    assert Store.merge_message("c", :not_a_payload) == :ok
    Store.put_raw_presence("g", %{"user" => %{"id" => "u"}, "activities" => :invalid})

    assert Enum.all?(Cache.stats(), fn {_, stat} ->
             not stat.enabled and stat.memory_bytes == 0
           end)

    assert Tables.table(:messages) == nil
    assert_raise ArgumentError, fn -> Cache.clear(:unknown) end
  end

  test "self-only caching and bot identity work without general users" do
    Lingo.TestBot.start(start: [:cache], cache: [only: [:members], members: :self])
    Store.put_current_user(%User{id: "me", username: "bot"})
    Store.put_member("g", %Member{user: %User{id: "me"}})
    Store.put_member("g", %Member{user: %User{id: "other"}})
    assert Cache.get_member("g", "me").user.id == "me"
    assert Cache.get_member("g", "other") == nil
    Cache.clear()
    assert Cache.get_current_user().username == "bot"
    assert Cache.get_user("me") == nil
    assert Cache.get_member("g", "me") == nil
  end

  test "separate bots have independent policy, identity and counters" do
    a = Lingo.TestBot.start(start: [:cache], cache: [only: [:guilds], guilds: [max_entries: 1]])
    b = Lingo.TestBot.start(start: [:cache], cache: false)

    Lingo.with_bot(a, fn ->
      Store.put_guild(%Guild{id: "g"})
      Store.put_current_user(%User{id: "a"})
    end)

    assert Cache.get_guild("g") == nil
    assert Cache.get_current_user() == nil
    assert Lingo.with_bot(a, fn -> Cache.stats().guilds.entries end) == 1
    assert Lingo.with_bot(b, fn -> Cache.stats().guilds.entries end) == 0
  end
end
