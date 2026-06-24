defmodule Lingo.Gateway.DispatcherTest do
  use ExUnit.Case

  alias Lingo.Gateway.Dispatcher
  alias Lingo.Type.AuditLogEntry

  defmodule AuditLogBot do
    use Lingo.Bot

    handle :guild_audit_log_entry_create, entry do
      send(:persistent_term.get({:lingo_test, :dispatcher_parent}), {:audit_log_entry, entry})
    end
  end

  setup do
    previous_bot = Lingo.Config.bot_module()

    :persistent_term.put({:lingo_test, :dispatcher_parent}, self())
    Lingo.Config.put(:bot_module, AuditLogBot)

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
end
