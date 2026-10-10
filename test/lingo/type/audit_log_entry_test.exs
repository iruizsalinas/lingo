defmodule Lingo.Type.AuditLogEntryTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.AuditLogEntry

  describe "AuditLogEntry" do
    test "parses gateway guild_id" do
      entry =
        AuditLogEntry.new(%{
          "id" => "entry1",
          "target_id" => "target1",
          "guild_id" => "guild1",
          "user_id" => "user1",
          "action_type" => 22
        })

      assert entry.guild_id == "guild1"
    end
  end
end
