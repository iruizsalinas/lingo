defmodule Lingo.PermissionsTest do
  use ExUnit.Case, async: true
  import Bitwise

  alias Lingo.Permissions

  describe "has?/2" do
    test "single permission present" do
      assert Permissions.has?(1 <<< 3, :administrator)
    end

    test "single permission absent" do
      refute Permissions.has?(1 <<< 3, :kick_members)
    end

    test "accepts string bitfield" do
      assert Permissions.has?("8", :administrator)
    end

    test "combined bitfield" do
      bitfield = bor(1 <<< 1, 1 <<< 2)
      assert Permissions.has?(bitfield, :kick_members)
      assert Permissions.has?(bitfield, :ban_members)
      refute Permissions.has?(bitfield, :administrator)
    end

    test "administrator is just bit 3, not a superset" do
      # has?/2 checks the raw bit, not Discord's admin-override logic
      refute Permissions.has?(1 <<< 3, :manage_guild)
    end

    test "large bitfield with many permissions" do
      bitfield =
        Permissions.resolve([:send_messages, :embed_links, :attach_files, :read_message_history])

      assert Permissions.has?(bitfield, :send_messages)
      assert Permissions.has?(bitfield, :read_message_history)
      refute Permissions.has?(bitfield, :manage_messages)
    end
  end

  describe "has_all?/2" do
    test "all present" do
      bitfield = bor(1 <<< 1, 1 <<< 2)
      assert Permissions.has_all?(bitfield, [:kick_members, :ban_members])
    end

    test "one missing" do
      refute Permissions.has_all?(1 <<< 1, [:kick_members, :ban_members])
    end

    test "empty list is always true" do
      assert Permissions.has_all?(0, [])
    end
  end

  describe "has_any?/2" do
    test "one present" do
      assert Permissions.has_any?(1 <<< 2, [:kick_members, :ban_members])
    end

    test "none present" do
      refute Permissions.has_any?(1 <<< 3, [:kick_members, :ban_members])
    end

    test "empty list is always false" do
      refute Permissions.has_any?(0xFFFFFFFF, [])
    end
  end

  describe "resolve/1" do
    test "combines multiple permissions" do
      result = Permissions.resolve([:kick_members, :ban_members])
      assert result == bor(1 <<< 1, 1 <<< 2)
    end

    test "single permission" do
      assert Permissions.resolve([:administrator]) == 1 <<< 3
    end

    test "empty list returns 0" do
      assert Permissions.resolve([]) == 0
    end

    test "raises on invalid permission" do
      assert_raise KeyError, fn ->
        Permissions.resolve([:nonexistent_permission])
      end
    end
  end

  describe "to_list/1" do
    test "extracts permission names from bitfield" do
      bitfield = bor(1 <<< 1, 1 <<< 2)
      perms = Permissions.to_list(bitfield)

      assert :kick_members in perms
      assert :ban_members in perms
      assert length(perms) == 2
    end

    test "accepts string bitfield" do
      perms = Permissions.to_list("8")
      assert perms == [:administrator]
    end

    test "zero returns empty list" do
      assert Permissions.to_list(0) == []
    end

    test "roundtrip: resolve then to_list" do
      original = [:send_messages, :manage_channels, :view_audit_log]
      bitfield = Permissions.resolve(original)
      result = Permissions.to_list(bitfield)
      assert Enum.sort(result) == Enum.sort(original)
    end
  end

  describe "all_permissions/0" do
    test "returns a non-empty list of atoms" do
      perms = Permissions.all_permissions()
      assert is_list(perms)
      assert length(perms) > 30
      assert Enum.all?(perms, &is_atom/1)
    end
  end
end
