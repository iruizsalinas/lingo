defmodule Lingo.Helper.RoleTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.{Channel, Guild, Member, Message, Role, User}

  setup do
    Lingo.TestBot.start(
      start: [:cache],
      cache: [
        guilds: true,
        channels: true,
        roles: true,
        users: true,
        members: true,
        messages: true,
        presences: true,
        voice_states: true
      ]
    )

    # seed a guild
    Lingo.Cache.Store.put_guild(%Guild{
      id: "guild1",
      name: "Test Guild",
      owner_id: "owner1"
    })

    # seed roles
    Lingo.Cache.Store.put_role("guild1", %Role{
      id: "guild1",
      name: "@everyone",
      position: 0,
      permissions: "0"
    })

    Lingo.Cache.Store.put_role("guild1", %Role{
      id: "role_high",
      name: "Admin",
      position: 10,
      permissions: "8",
      managed: false
    })

    Lingo.Cache.Store.put_role("guild1", %Role{
      id: "role_mid",
      name: "Mod",
      position: 5,
      permissions: "0",
      managed: false
    })

    Lingo.Cache.Store.put_role("guild1", %Role{
      id: "role_low",
      name: "Member",
      position: 1,
      permissions: "0",
      managed: false,
      color: 0xFF0000
    })

    Lingo.Cache.Store.put_role("guild1", %Role{
      id: "role_managed",
      name: "Bot Role",
      position: 8,
      permissions: "0",
      managed: true
    })

    # seed bot user
    Lingo.Cache.Store.put_current_user(%User{
      id: "bot1",
      username: "TestBot",
      global_name: "Test Bot"
    })

    # seed bot member (has high role)
    Lingo.Cache.Store.put_member("guild1", %Member{
      user: %User{id: "bot1", username: "TestBot", global_name: "Test Bot"},
      roles: ["role_high"]
    })

    # seed another member (has mid role)
    Lingo.Cache.Store.put_member("guild1", %Member{
      user: %User{id: "user1", username: "someuser", global_name: "Some User"},
      nick: "Nickname",
      roles: ["role_mid", "role_low"]
    })

    # seed guild owner
    Lingo.Cache.Store.put_member("guild1", %Member{
      user: %User{id: "owner1", username: "owner", global_name: "Owner"},
      roles: ["role_high"]
    })

    # seed a channel with overwrites
    Lingo.Cache.Store.put_channel(%Channel{
      id: "ch1",
      guild_id: "guild1",
      type: :guild_text,
      permission_overwrites: [
        %{id: "guild1", type: :role, allow: "0", deny: "1024"},
        %{id: "role_mid", type: :role, allow: "1024", deny: "0"}
      ]
    })

    # seed a message
    Lingo.Cache.Store.put_message(%Message{
      id: "msg1",
      channel_id: "ch1",
      author: %User{id: "user1", username: "someuser"},
      content: "hello"
    })

    Lingo.Cache.Store.put_message(%Message{
      id: "msg2",
      channel_id: "ch1",
      author: %User{id: "bot1", username: "TestBot"},
      content: "bot message"
    })

    :ok
  end

  describe "role_editable?" do
    test "returns true for a role below the bot's highest" do
      assert Lingo.Helper.Role.editable?("guild1", "role_mid")
    end

    test "returns false for a managed role" do
      refute Lingo.Helper.Role.editable?("guild1", "role_managed")
    end

    test "returns false for the @everyone role" do
      refute Lingo.Helper.Role.editable?("guild1", "guild1")
    end

    test "returns false for a role at or above bot's position" do
      refute Lingo.Helper.Role.editable?("guild1", "role_high")
    end

    test "returns false for unknown role" do
      refute Lingo.Helper.Role.editable?("guild1", "nonexistent")
    end
  end

  describe "compare_role_positions" do
    test "returns :gt when first role is higher" do
      assert Lingo.Helper.Role.compare("guild1", "role_high", "role_mid") == :gt
    end

    test "returns :lt when first role is lower" do
      assert Lingo.Helper.Role.compare("guild1", "role_low", "role_mid") == :lt
    end

    test "returns nil for unknown role" do
      assert Lingo.Helper.Role.compare("guild1", "role_high", "nope") == nil
    end
  end
end
