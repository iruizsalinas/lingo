defmodule Lingo.Cache.PolicyTest do
  use ExUnit.Case, async: true
  alias Lingo.Cache.Policy

  test "defaults, allowlists, overrides, zero limits and legacy options" do
    assert map_size(Policy.normalize([])) == 8
    assert Policy.normalize([]).messages.scope_limit == 200
    assert Policy.normalize(false) == %{}
    assert Policy.normalize(only: []) == %{}
    assert Map.keys(Policy.normalize(only: [:guilds], guilds: true)) == [:guilds]
    assert Policy.normalize(guilds: false)[:guilds] == nil

    assert Policy.normalize(enabled: [:messages], max_messages_per_channel: 3).messages.scope_limit ==
             3

    assert Policy.normalize(messages: [max_entries: 0])[:messages] == nil
    assert Policy.normalize(messages: [ttl: 0])[:messages] == nil
    assert Policy.normalize(users: [max_entries: 0, keep: :self]).users.keep == :self
    assert Policy.normalize(:permissions).members.filter == :self
    assert Policy.normalize(:permissions)[:messages] == nil
  end

  test "invalid policies fail before bot startup" do
    for config <- [
          true,
          :unknown,
          [:guilds],
          [only: :guilds],
          [only: [:unknown]],
          [enabled: [:unknown]],
          [only: [], enabled: []],
          [unknown: true],
          [guilds: :self],
          [messages: :self],
          [users: [max_entries_per_guild: 1]],
          [members: [max_entries_per_channel: 1]],
          [messages: [max_entries: -1]],
          [messages: [ttl: 1.5]],
          [messages: [filter: fn _ -> true end]],
          [members: [keep: :unknown]],
          [guilds: false, max_messages_per_channel: -1],
          [only: [], users: [max_entries: -1]]
        ] do
      assert_raise ArgumentError, fn -> Policy.normalize(config) end
    end

    assert_raise ArgumentError, fn ->
      Lingo.Config.validate!(bot: __MODULE__, token: "test", cache: [members: [ttl: -1]])
    end
  end

  test "keep overrides admission with an explicit bot context" do
    bot = Lingo.TestBot.start(user_id: "me")
    policy = Policy.normalize(users: [filter: :none, keep: :self]).users
    context = Policy.context(:users, "me")
    assert context == %{bot: bot, user_id: "me", resource: :users, key: "me"}
    assert Policy.decision(policy, %Lingo.Type.User{id: "me"}, context) == {true, true}
    assert Policy.decision(policy, %Lingo.Type.User{id: "other"}, context) == {false, false}
  end
end
