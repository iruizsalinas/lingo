defmodule Lingo.Gateway.DispatcherTest do
  use ExUnit.Case

  alias Lingo.Gateway.Dispatcher
  alias Lingo.Type.{AuditLogEntry, Channel, Guild, Invite, Member, Message, Presence, Role}

  defmodule DispatchBot do
    use Lingo.Bot

    handle :guild_audit_log_entry_create, entry do
      send(:persistent_term.get({:lingo_test, :dispatcher_parent}), {:audit_log_entry, entry})
    end

    handle :guild_create, guild do
      send(:persistent_term.get({:lingo_test, :dispatcher_parent}), {:guild_create, guild})
    end

    handle :invite_create, invite do
      send(:persistent_term.get({:lingo_test, :dispatcher_parent}), {:invite_create, invite})
    end

    handle :guild_role_create, role do
      send(:persistent_term.get({:lingo_test, :dispatcher_parent}), {:guild_role_create, role})
    end

    handle :guild_role_update, data do
      send(:persistent_term.get({:lingo_test, :dispatcher_parent}), {:guild_role_update, data})
    end

    handle :guild_members_chunk, data do
      send(:persistent_term.get({:lingo_test, :dispatcher_parent}), {:guild_members_chunk, data})
    end

    handle :message_create, message do
      send(:persistent_term.get({:lingo_test, :dispatcher_parent}), {:message_create, message})
    end

    handle :message_update, data do
      send(:persistent_term.get({:lingo_test, :dispatcher_parent}), {:message_update, data})
    end

    handle :presence_update, data do
      send(:persistent_term.get({:lingo_test, :dispatcher_parent}), {:presence_update, data})
    end
  end

  setup do
    start_supervised!(Lingo.Cache)

    previous_bot = Lingo.Config.bot_module()

    :persistent_term.put({:lingo_test, :dispatcher_parent}, self())
    Lingo.Config.put(:bot_module, DispatchBot)

    on_exit(fn ->
      Lingo.Config.put(:bot_module, previous_bot)
      :persistent_term.erase({:lingo_test, :dispatcher_parent})
    end)
  end

  test "dispatches guild audit log entry create with guild_id intact" do
    Dispatcher.dispatch(:guild_audit_log_entry_create, %{
      "id" => "entry1",
      "target_id" => "target1",
      "guild_id" => "guild1",
      "user_id" => "user1",
      "action_type" => 22,
      "changes" => [%{"key" => "communication_disabled_until"}]
    })

    assert_receive {:audit_log_entry, %AuditLogEntry{} = entry}

    assert entry.id == "entry1"
    assert entry.guild_id == "guild1"
    assert entry.target_id == "target1"
    assert entry.user_id == "user1"
    assert entry.action_type == 22
    assert entry.changes == [%{"key" => "communication_disabled_until"}]
  end

  test "a full channel update replaces an obfuscated cached channel" do
    Dispatcher.dispatch(:channel_create, %{
      "id" => "channel1",
      "guild_id" => "guild1",
      "type" => 0,
      "name" => "___hidden___",
      "flags" => 131_072,
      "permission_overwrites" => [
        %{"id" => "guild1", "type" => 0, "allow" => "0", "deny" => "1024"}
      ]
    })

    assert %Channel{} = hidden = Lingo.Cache.get_channel("channel1")
    assert Channel.obfuscated?(hidden)

    Dispatcher.dispatch(:channel_update, %{
      "id" => "channel1",
      "guild_id" => "guild1",
      "type" => 0,
      "name" => "private-room",
      "flags" => 0,
      "permission_overwrites" => []
    })

    assert %Channel{name: "private-room"} = visible = Lingo.Cache.get_channel("channel1")
    refute Channel.obfuscated?(visible)
  end

  test "dispatches invite create with gateway context intact" do
    Dispatcher.dispatch(:invite_create, %{
      "code" => "abc123",
      "guild_id" => "guild1",
      "channel_id" => "channel1",
      "role_ids" => ["role1"],
      "created_at" => "2026-01-01T00:00:00Z",
      "max_age" => 3600,
      "max_uses" => 5,
      "temporary" => false,
      "uses" => 0
    })

    assert_receive {:invite_create, %Invite{} = invite}

    assert invite.code == "abc123"
    assert invite.guild_id == "guild1"
    assert invite.channel_id == "channel1"
    assert invite.role_ids == ["role1"]
    assert invite.uses == 0
  end

  test "dispatches guild create with nested member and cached presence context intact" do
    Dispatcher.dispatch(:guild_create, %{
      "id" => "guild1",
      "name" => "Guild",
      "owner_id" => "owner1",
      "members" => [
        %{
          "user" => %{"id" => "user1", "username" => "alice", "discriminator" => "0"},
          "roles" => ["role1"]
        }
      ],
      "presences" => [
        %{
          "user" => %{"id" => "user1", "username" => "alice", "discriminator" => "0"},
          "status" => "online",
          "activities" => []
        }
      ]
    })

    assert_receive {:guild_create, %Guild{members: [%Member{} = member]}}

    assert member.guild_id == "guild1"
    assert member.user.id == "user1"

    assert %Member{user: %{id: "user1"}, guild_id: "guild1"} =
             Lingo.Cache.get_member("guild1", "user1")

    assert %Presence{user: %{id: "user1"}, guild_id: "guild1"} =
             Lingo.Cache.get_presence("guild1", "user1")
  end

  test "dispatches guild role create with guild_id intact" do
    Dispatcher.dispatch(:guild_role_create, %{
      "guild_id" => "guild1",
      "role" => %{
        "id" => "role1",
        "name" => "Admin",
        "permissions" => "0"
      }
    })

    assert_receive {:guild_role_create, %Role{} = role}

    assert role.id == "role1"
    assert role.guild_id == "guild1"
    assert role.name == "Admin"
  end

  test "dispatches guild role update with guild_id intact" do
    Dispatcher.dispatch(:guild_role_update, %{
      "guild_id" => "guild1",
      "role" => %{
        "id" => "role1",
        "name" => "Admin",
        "permissions" => "0"
      }
    })

    assert_receive {:guild_role_update, %{old: nil, new: %Role{} = role}}

    assert role.id == "role1"
    assert role.guild_id == "guild1"
    assert role.name == "Admin"
  end

  test "dispatches guild members chunk with member and presence context intact" do
    Dispatcher.dispatch(:guild_members_chunk, %{
      "guild_id" => "guild1",
      "members" => [
        %{
          "user" => %{"id" => "user1", "username" => "alice", "discriminator" => "0"},
          "roles" => ["role1"],
          "joined_at" => "2026-01-01T00:00:00Z"
        }
      ],
      "presences" => [
        %{
          "user" => %{"id" => "user1", "username" => "alice", "discriminator" => "0"},
          "status" => "online",
          "activities" => []
        }
      ],
      "chunk_index" => 0,
      "chunk_count" => 1,
      "nonce" => "nonce1"
    })

    assert_receive {:guild_members_chunk,
                    %{
                      guild_id: "guild1",
                      members: [%Member{} = member],
                      presences: [%Presence{} = presence],
                      chunk_index: 0,
                      chunk_count: 1,
                      nonce: "nonce1"
                    }}

    assert member.guild_id == "guild1"
    assert member.user.id == "user1"
    assert presence.guild_id == "guild1"
    assert presence.user.id == "user1"
    assert presence.status == :online

    assert %Member{user: %{id: "user1"}, guild_id: "guild1"} =
             Lingo.Cache.get_member("guild1", "user1")

    assert %Presence{user: %{id: "user1"}, guild_id: "guild1"} =
             Lingo.Cache.get_presence("guild1", "user1")
  end

  test "dispatches message create with channel_type intact" do
    Dispatcher.dispatch(:message_create, %{
      "id" => "message1",
      "channel_id" => "channel1",
      "channel_type" => 0,
      "guild_id" => "guild1",
      "author" => %{"id" => "user1", "username" => "alice", "discriminator" => "0"},
      "member" => %{"nick" => "Alice", "roles" => ["role1"]},
      "content" => "hello",
      "timestamp" => "2026-01-01T00:00:00Z"
    })

    assert_receive {:message_create, %Message{} = message}

    assert message.id == "message1"
    assert message.channel_type == 0
    assert message.guild_id == "guild1"
    assert message.member.guild_id == "guild1"
    assert message.member.user.id == "user1"

    assert %Message{channel_type: 0, member: %Member{guild_id: "guild1", user: %{id: "user1"}}} =
             Lingo.Cache.get_message("channel1", "message1")
  end

  test "dispatches message update with channel_type intact" do
    Dispatcher.dispatch(:message_update, %{
      "id" => "message1",
      "channel_id" => "channel1",
      "channel_type" => 0,
      "guild_id" => "guild1",
      "content" => "edited",
      "timestamp" => "2026-01-01T00:00:00Z"
    })

    assert_receive {:message_update, %{old: nil, new: %Message{} = message}}

    assert message.id == "message1"
    assert message.channel_type == 0
    assert message.guild_id == "guild1"
  end

  test "dispatches message update with merged cached message when update is partial" do
    Dispatcher.dispatch(:message_create, %{
      "id" => "message2",
      "channel_id" => "channel1",
      "channel_type" => 0,
      "guild_id" => "guild1",
      "author" => %{"id" => "user1", "username" => "alice", "discriminator" => "0"},
      "member" => %{"nick" => "Alice", "roles" => ["role1"]},
      "content" => "before",
      "timestamp" => "2026-01-01T00:00:00Z"
    })

    assert_receive {:message_create, %Message{}}

    Dispatcher.dispatch(:message_update, %{
      "id" => "message2",
      "channel_id" => "channel1",
      "content" => "after",
      "member" => %{"nick" => "Edited", "roles" => ["role2"]}
    })

    assert_receive {:message_update, %{old: %Message{content: "before"}, new: %Message{} = new}}

    assert new.content == "after"
    assert new.guild_id == "guild1"
    assert new.channel_type == 0
    assert new.author.id == "user1"
    assert %Member{guild_id: "guild1", nick: "Edited", user: %{id: "user1"}} = new.member
  end

  test "dispatches presence update with cached user details when payload user is partial" do
    Lingo.Cache.put_user(%Lingo.Type.User{id: "user1", username: "alice", bot: true})

    Dispatcher.dispatch(:presence_update, %{
      "guild_id" => "guild1",
      "user" => %{"id" => "user1"},
      "status" => "idle",
      "activities" => []
    })

    assert_receive {:presence_update, %{old: nil, new: %Presence{} = presence}}

    assert presence.guild_id == "guild1"
    assert presence.status == :idle
    assert presence.user.username == "alice"
    assert presence.user.bot == true
  end

  describe "cache bookkeeping" do
    test "GUILD_CREATE caches active threads" do
      Dispatcher.dispatch(:guild_create, %{
        "id" => "g_threads",
        "name" => "Threads",
        "channels" => [%{"id" => "c_parent", "type" => 0}],
        "threads" => [%{"id" => "t_active", "type" => 11, "parent_id" => "c_parent"}]
      })

      assert %Channel{id: "t_active", guild_id: "g_threads"} = Lingo.Cache.get_channel("t_active")
    end

    test "GUILD_UPDATE keeps GUILD_CREATE-only fields" do
      Dispatcher.dispatch(:guild_create, %{
        "id" => "g_upd",
        "name" => "Old",
        "member_count" => 10,
        "large" => true,
        "joined_at" => "2024-01-01T00:00:00+00:00"
      })

      Dispatcher.dispatch(:guild_update, %{"id" => "g_upd", "name" => "New"})

      guild = Lingo.Cache.get_guild("g_upd")
      assert guild.name == "New"
      assert guild.member_count == 10
      assert guild.large == true
      assert guild.joined_at == "2024-01-01T00:00:00+00:00"
    end

    test "member add and remove keep member_count current" do
      Dispatcher.dispatch(:guild_create, %{"id" => "g_count", "member_count" => 5})
      user = %{"id" => "u_count", "username" => "c"}

      Dispatcher.dispatch(:guild_member_add, %{"guild_id" => "g_count", "user" => user})
      assert Lingo.Cache.get_guild("g_count").member_count == 6

      Dispatcher.dispatch(:guild_member_remove, %{"guild_id" => "g_count", "user" => user})
      assert Lingo.Cache.get_guild("g_count").member_count == 5
    end

    test "USER_UPDATE refreshes the current user" do
      Dispatcher.dispatch(:shard_ready, %{"user" => %{"id" => "me", "username" => "old"}})
      Dispatcher.dispatch(:user_update, %{"id" => "me", "username" => "new"})

      assert Lingo.Cache.get_current_user().username == "new"
    end
  end
end
