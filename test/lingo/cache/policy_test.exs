defmodule Lingo.Cache.PolicyTest do
  use ExUnit.Case, async: true
  alias Lingo.Cache.Policy

  test "defaults, allowlists, overrides, zero limits and legacy options" do
    assert Policy.normalize([]) == %{}
    assert Policy.normalize(nil) == Policy.normalize([])
    assert Policy.normalize([])[:messages] == nil
    assert Policy.normalize(messages: true).messages.scope_limit == 200
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
          [only: [], users: [max_entries: -1]],
          [messages: [compact: :yes]],
          [users: [compressed: 1]],
          [compact: :yes],
          [compressed: 1, only: []],
          [compressed: :yes, messages: [compressed: false]],
          [users: [:compact]]
        ] do
      assert_raise ArgumentError, fn -> Policy.normalize(config) end
    end

    assert_raise ArgumentError, fn ->
      Lingo.Config.validate!(bot: __MODULE__, token: "test", cache: [members: [ttl: -1]])
    end
  end

  test "global storage settings apply only to enabled resources with local precedence" do
    assert Policy.normalize(compact: false, compressed: true) == %{}

    policies =
      Policy.normalize(compact: false, compressed: true, guilds: true, roles: [compressed: false])

    assert map_size(policies) == 2
    for name <- [:messages, :presences, :voice_states], do: assert(policies[name] == nil)
    assert policies.guilds.compact == false
    assert policies.guilds.compressed == true
    assert policies.roles.compressed == false
    assert policies[:users] == nil
    assert policies[:members] == nil

    policies =
      Policy.normalize(
        only: [:messages],
        compact: false,
        compressed: true,
        messages: [compact: true, ttl: 60_000]
      )

    assert Map.keys(policies) == [:messages]
    assert policies.messages.compact == true
    assert policies.messages.compressed == true
    assert policies.messages.scope_limit == 200
    assert policies.messages.ttl == 60_000
    assert Policy.normalize(only: [:messages]).messages.scope_limit == 200
  end

  test "explicit resource policies enable normal admission and self remains opt-in" do
    assert Policy.normalize(users: [compact: false]).users.filter == :all
    assert Policy.normalize(members: [max_entries: 10]).members.keep == :none
    assert Policy.normalize(users: :self).users.filter == :self
    assert Policy.normalize(members: :self).members.keep == :self
    assert Policy.normalize(users: true).users.filter == :all
    assert Policy.normalize(users: true).users.keep == :none
    assert Policy.normalize(members: [filter: :all, keep: :none]).members.filter == :all
    assert Policy.normalize(messages: []).messages.scope_limit == 200
    assert Policy.normalize(presences: []).presences.filter == :all
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
