defmodule Lingo.Gateway.DispatcherTest do
  use ExUnit.Case, async: true

  alias Lingo.Event
  alias Lingo.Gateway.Dispatcher
  alias Lingo.Type.{AuditLogEntry, Channel, Guild, Invite, Member, Presence}

  defmodule DispatchBot do
    use Lingo.Bot

    @impl true
    def handle_event(event, data), do: send(Lingo.Instance.get(:test_pid), {event, data})

    @impl true
    def handle_error(error, source),
      do: send(Lingo.Instance.get(:test_pid), {:error, error, source})
  end

  setup do
    %{
      bot:
        Lingo.TestBot.start(
          bot: DispatchBot,
          test_pid: self(),
          start: [:cache, :collector],
          cache: [
            guilds: true,
            channels: true,
            roles: true,
            users: true,
            members: true,
            messages: true,
            presences: true
          ]
        )
    }
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

    assert_receive {:guild_audit_log_entry_create, %AuditLogEntry{} = entry}

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

    assert %Channel{} = hidden = Lingo.Cache.Channel.get("channel1")
    assert Channel.obfuscated?(hidden)

    Dispatcher.dispatch(:channel_update, %{
      "id" => "channel1",
      "guild_id" => "guild1",
      "type" => 0,
      "name" => "private-room",
      "flags" => 0,
      "permission_overwrites" => []
    })

    assert %Channel{name: "private-room"} = visible = Lingo.Cache.Channel.get("channel1")
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
             Lingo.Cache.Member.get("guild1", "user1")

    assert %Presence{user: %{id: "user1"}, guild_id: "guild1"} =
             Lingo.Cache.Presence.get("guild1", "user1")
  end

  describe "cache bookkeeping" do
    test "GUILD_CREATE caches active threads" do
      Dispatcher.dispatch(:guild_create, %{
        "id" => "g_threads",
        "name" => "Threads",
        "channels" => [%{"id" => "c_parent", "type" => 0}],
        "threads" => [%{"id" => "t_active", "type" => 11, "parent_id" => "c_parent"}]
      })

      assert %Channel{id: "t_active", guild_id: "g_threads"} = Lingo.Cache.Channel.get("t_active")
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

      guild = Lingo.Cache.Guild.get("g_upd")
      assert guild.name == "New"
      assert guild.member_count == 10
      assert guild.large == true
      assert guild.joined_at == ~U[2024-01-01 00:00:00Z]
    end

    test "member add and remove keep member_count current" do
      Dispatcher.dispatch(:guild_create, %{"id" => "g_count", "member_count" => 5})
      user = %{"id" => "u_count", "username" => "c"}

      Dispatcher.dispatch(:guild_member_add, %{"guild_id" => "g_count", "user" => user})
      assert Lingo.Cache.Guild.get("g_count").member_count == 6

      Dispatcher.dispatch(:guild_member_remove, %{"guild_id" => "g_count", "user" => user})
      assert Lingo.Cache.Guild.get("g_count").member_count == 5
    end

    test "USER_UPDATE refreshes the current user" do
      Dispatcher.dispatch(:ready, %{"user" => %{"id" => "me", "username" => "old"}})
      Dispatcher.dispatch(:user_update, %{"id" => "me", "username" => "new"})

      assert Lingo.Cache.User.get_current().username == "new"
    end
  end

  describe "deletes" do
    test "carry the cached resource as old" do
      Dispatcher.dispatch(:message_create, %{
        "id" => "m1",
        "channel_id" => "c1",
        "content" => "hi"
      })

      Dispatcher.dispatch(:message_delete, %{"id" => "m1", "channel_id" => "c1"})

      assert_receive {:message_delete,
                      %Event.MessageDelete{id: "m1", old: %Lingo.Type.Message{content: "hi"}}}

      assert Lingo.Cache.Message.get("c1", "m1") == nil

      Dispatcher.dispatch(:message_create, %{"id" => "m2", "channel_id" => "c1", "content" => "a"})

      Dispatcher.dispatch(:message_delete_bulk, %{"ids" => ["m2", "m3"], "channel_id" => "c1"})

      assert_receive {:message_delete_bulk,
                      %Event.MessageDeleteBulk{ids: ["m2", "m3"], old: [%{id: "m2"}]}}
    end

    test "carry nil as old when the resource wasn't cached" do
      Dispatcher.dispatch(:guild_role_delete, %{"guild_id" => "g", "role_id" => "r"})
      assert_receive {:guild_role_delete, %Event.GuildRoleDelete{role_id: "r", old: nil}}

      Dispatcher.dispatch(:guild_emojis_update, %{"guild_id" => "nowhere", "emojis" => []})
      assert_receive {:guild_emojis_update, %Event.GuildEmojisUpdate{emojis: [], old: nil}}
    end

    test "a guild outage keeps the guild, leaving it removes it" do
      Dispatcher.dispatch(:guild_create, %{"id" => "g_out", "name" => "G"})

      Dispatcher.dispatch(:guild_delete, %{"id" => "g_out", "unavailable" => true})
      assert_receive {:guild_delete, %Event.GuildDelete{unavailable: true, old: %Guild{}}}
      assert %Guild{unavailable: true} = Lingo.Cache.Guild.get("g_out")

      Dispatcher.dispatch(:guild_delete, %{"id" => "g_out"})
      assert_receive {:guild_delete, %Event.GuildDelete{unavailable: false, old: %Guild{}}}
      assert Lingo.Cache.Guild.get("g_out") == nil
    end

    test "channel deletes carry the channel Discord sends" do
      Dispatcher.dispatch(:channel_delete, %{"id" => "c_del", "guild_id" => "g", "type" => 0})
      assert_receive {:channel_delete, %Channel{id: "c_del", type: :guild_text}}
    end
  end

  describe "delivery" do
    test "unknown events arrive as :unknown, with Discord's name and data" do
      Dispatcher.dispatch({:unknown, "SOMETHING_NEW"}, %{"a" => 1})
      assert_receive {:unknown, %Event.Unknown{type: "SOMETHING_NEW", data: %{"a" => 1}}}
    end

    test "events Lingo keeps to itself don't reach the bot" do
      Dispatcher.dispatch(:voice_server_update, %{"guild_id" => "g", "token" => "t"})
      refute_receive {:voice_server_update, _}, 100
    end

    @tag :capture_log
    test "an event that fails to parse goes to handle_error/2 with the raw data" do
      Dispatcher.dispatch(:guild_role_create, %{"guild_id" => "g", "role" => "not a role"})

      assert_receive {:error,
                      %Lingo.EventError{event: :guild_role_create, exception: %BadMapError{}},
                      {:guild_role_create, %{"guild_id" => "g", "role" => "not a role"}}}

      refute_receive {:guild_role_create, _}, 100
    end
  end
end
