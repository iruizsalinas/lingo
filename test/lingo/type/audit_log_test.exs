defmodule Lingo.Type.AuditLogTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.{
    ApplicationCommand,
    AuditLog,
    AuditLogEntry,
    AutoModerationRule,
    Channel,
    Integration,
    ScheduledEvent,
    User,
    Webhook
  }

  test "the resources an audit log refers to are parsed" do
    log =
      AuditLog.new(%{
        "application_commands" => [%{"id" => "c1", "name" => "ping", "type" => 1}],
        "audit_log_entries" => [%{"id" => "e1", "action_type" => 22}],
        "auto_moderation_rules" => [%{"id" => "r1", "trigger_type" => 1}],
        "guild_scheduled_events" => [%{"id" => "s1", "status" => 1}],
        "integrations" => [
          %{
            "id" => "33590653072239123",
            "name" => "A Name",
            "type" => "twitch",
            "account" => %{"name" => "twitchusername", "id" => "1234567"},
            "application_id" => "94651234501213162"
          }
        ],
        "threads" => [%{"id" => "t1", "type" => 11}],
        "users" => [%{"id" => "u1"}],
        "webhooks" => [%{"id" => "w1", "type" => 1}]
      })

    assert [%ApplicationCommand{id: "c1", name: "ping"}] = log.application_commands
    assert [%AuditLogEntry{id: "e1", action_type: :member_ban_add}] = log.audit_log_entries
    assert [%AutoModerationRule{id: "r1", trigger_type: :keyword}] = log.auto_moderation_rules
    assert [%ScheduledEvent{id: "s1", status: :scheduled}] = log.guild_scheduled_events
    assert [%Channel{id: "t1", type: :public_thread}] = log.threads
    assert [%User{id: "u1"}] = log.users
    assert [%Webhook{id: "w1", type: :incoming}] = log.webhooks

    assert [
             %Integration{
               name: "A Name",
               type: "twitch",
               account: %{id: "1234567", name: "twitchusername"},
               application_id: "94651234501213162"
             }
           ] = log.integrations
  end

  test "lists Discord leaves out are empty" do
    assert %AuditLog{application_commands: [], webhooks: []} = AuditLog.new(%{})
  end
end
