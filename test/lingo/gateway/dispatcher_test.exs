defmodule Lingo.Gateway.DispatcherTest do
  use ExUnit.Case

  alias Lingo.Gateway.Dispatcher
  alias Lingo.Type.{AuditLogEntry, Invite, Role}

  defmodule DispatchBot do
    use Lingo.Bot

    handle :guild_audit_log_entry_create, entry do
      send(:persistent_term.get({:lingo_test, :dispatcher_parent}), {:audit_log_entry, entry})
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
end
