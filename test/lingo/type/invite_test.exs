defmodule Lingo.Type.InviteTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.{Invite, Role, ScheduledEvent}

  describe "Invite" do
    test "parses current optional invite fields" do
      invite =
        Invite.new(%{
          "type" => 0,
          "code" => "abc123",
          "guild_id" => "guild1",
          "channel_id" => "channel1",
          "target_application" => %{"id" => "app1", "name" => "Activity"},
          "role_ids" => ["role1"],
          "guild_scheduled_event" => %{
            "id" => "event1",
            "guild_id" => "guild1",
            "name" => "Launch",
            "scheduled_start_time" => "2026-01-01T00:00:00Z",
            "privacy_level" => 2,
            "status" => 1,
            "entity_type" => 2
          },
          "roles" => [
            %{
              "id" => "role1",
              "name" => "Guest",
              "position" => 1,
              "color" => 12,
              "icon" => "icon_hash",
              "unicode_emoji" => nil
            }
          ]
        })

      assert invite.guild_id == "guild1"
      assert invite.channel_id == "channel1"
      assert invite.role_ids == ["role1"]
      assert %Lingo.Type.Application{id: "app1", name: "Activity"} = invite.target_application
      assert %ScheduledEvent{} = invite.guild_scheduled_event
      assert invite.guild_scheduled_event.id == "event1"
      assert [%Role{} = role] = invite.roles
      assert role.id == "role1"
      assert role.guild_id == "guild1"
      assert role.name == "Guest"
      assert role.position == 1
    end
  end
end
