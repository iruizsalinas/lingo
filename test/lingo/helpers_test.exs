defmodule Lingo.HelpersTest do
  use ExUnit.Case

  alias Lingo.{Cache, Helpers}
  alias Lingo.Type.{Channel, Guild, Member, Message, Role, User}

  setup do
    start_supervised!(Cache)

    # seed a guild
    Cache.put_guild(%Guild{
      id: "guild1",
      name: "Test Guild",
      owner_id: "owner1"
    })

    # seed roles
    Cache.put_role("guild1", %Role{id: "guild1", name: "@everyone", position: 0, permissions: "0"})

    Cache.put_role("guild1", %Role{
      id: "role_high",
      name: "Admin",
      position: 10,
      permissions: "8",
      managed: false
    })

    Cache.put_role("guild1", %Role{
      id: "role_mid",
      name: "Mod",
      position: 5,
      permissions: "0",
      managed: false
    })

    Cache.put_role("guild1", %Role{
      id: "role_low",
      name: "Member",
      position: 1,
      permissions: "0",
      managed: false,
      color: 0xFF0000
    })

    Cache.put_role("guild1", %Role{
      id: "role_managed",
      name: "Bot Role",
      position: 8,
      permissions: "0",
      managed: true
    })

    # seed bot user
    Cache.put_current_user(%User{id: "bot1", username: "TestBot", global_name: "Test Bot"})

    # seed bot member (has high role)
    Cache.put_member("guild1", %Member{
      user: %User{id: "bot1", username: "TestBot", global_name: "Test Bot"},
      roles: ["role_high"]
    })

    # seed another member (has mid role)
    Cache.put_member("guild1", %Member{
      user: %User{id: "user1", username: "someuser", global_name: "Some User"},
      nick: "Nickname",
      roles: ["role_mid", "role_low"]
    })

    # seed guild owner
    Cache.put_member("guild1", %Member{
      user: %User{id: "owner1", username: "owner", global_name: "Owner"},
      roles: ["role_high"]
    })

    # seed a channel with overwrites
    Cache.put_channel(%Channel{
      id: "ch1",
      guild_id: "guild1",
      type: :guild_text,
      permission_overwrites: [
        %{id: "guild1", type: :role, allow: "0", deny: "1024"},
        %{id: "role_mid", type: :role, allow: "1024", deny: "0"}
      ]
    })

    # seed a message
    Cache.put_message(%Message{
      id: "msg1",
      channel_id: "ch1",
      author: %User{id: "user1", username: "someuser"},
      content: "hello"
    })

    Cache.put_message(%Message{
      id: "msg2",
      channel_id: "ch1",
      author: %User{id: "bot1", username: "TestBot"},
      content: "bot message"
    })

    :ok
  end

  describe "role_editable?" do
    test "returns true for a role below the bot's highest" do
      assert Helpers.role_editable?("guild1", "role_mid")
    end

    test "returns false for a managed role" do
      refute Helpers.role_editable?("guild1", "role_managed")
    end

    test "returns false for the @everyone role" do
      refute Helpers.role_editable?("guild1", "guild1")
    end

    test "returns false for a role at or above bot's position" do
      refute Helpers.role_editable?("guild1", "role_high")
    end

    test "returns false for unknown role" do
      refute Helpers.role_editable?("guild1", "nonexistent")
    end
  end

  describe "compare_role_positions" do
    test "returns :gt when first role is higher" do
      assert Helpers.compare_role_positions("guild1", "role_high", "role_mid") == :gt
    end

    test "returns :lt when first role is lower" do
      assert Helpers.compare_role_positions("guild1", "role_low", "role_mid") == :lt
    end

    test "returns nil for unknown role" do
      assert Helpers.compare_role_positions("guild1", "role_high", "nope") == nil
    end
  end

  describe "member_manageable?" do
    test "returns true for a member below the bot" do
      assert Helpers.member_manageable?("guild1", "user1")
    end

    test "returns false for the guild owner" do
      refute Helpers.member_manageable?("guild1", "owner1")
    end

    test "returns false for the bot itself" do
      refute Helpers.member_manageable?("guild1", "bot1")
    end

    test "returns false for unknown member" do
      refute Helpers.member_manageable?("guild1", "nobody")
    end
  end

  describe "member_kickable?" do
    test "returns true when manageable and bot has kick permission" do
      # bot has admin (permission 8 = administrator), which implies kick
      assert Helpers.member_kickable?("guild1", "user1")
    end
  end

  describe "member_bannable?" do
    test "returns true when manageable and bot has ban permission" do
      assert Helpers.member_bannable?("guild1", "user1")
    end
  end

  describe "member_permissions" do
    test "returns combined permissions for a member" do
      perms = Helpers.member_permissions("guild1", "bot1")
      # role_high has permissions "8" (administrator)
      assert Lingo.Permissions.has?(perms, :administrator)
    end

    test "returns all permissions for guild owner" do
      perms = Helpers.member_permissions("guild1", "owner1")
      assert Lingo.Permissions.has?(perms, :administrator)
      assert Lingo.Permissions.has?(perms, :manage_guild)
      assert Lingo.Permissions.has?(perms, :ban_members)
    end

    test "returns 0 for unknown member" do
      assert Helpers.member_permissions("guild1", "nobody") == 0
    end
  end

  describe "member_display_name" do
    test "returns nick when set" do
      assert Helpers.member_display_name("guild1", "user1") == "Nickname"
    end

    test "falls back to global_name or username when no nick" do
      name = Helpers.member_display_name("guild1", "bot1")
      assert is_binary(name)
    end

    test "returns nil for unknown member" do
      assert Helpers.member_display_name("guild1", "nobody") == nil
    end
  end

  describe "member_display_color" do
    test "returns color from highest colored role" do
      # user1 has role_low (color 0xFF0000) and role_mid (color 0)
      assert Helpers.member_display_color("guild1", "user1") == 0xFF0000
    end

    test "returns 0 when no colored roles" do
      assert Helpers.member_display_color("guild1", "bot1") == 0
    end

    test "returns 0 for unknown member" do
      assert Helpers.member_display_color("guild1", "nobody") == 0
    end
  end

  describe "permissions_for" do
    test "computes effective permissions in a channel" do
      perms = Helpers.permissions_for("ch1", "user1")
      # user1 has role_mid which is allowed view_channel (1024) in ch1
      assert Lingo.Permissions.has?(perms, :view_channel)
    end

    test "returns 0 for unknown channel" do
      assert Helpers.permissions_for("nonexistent", "user1") == 0
    end
  end

  describe "channel_viewable?" do
    test "returns true when bot can see the channel" do
      # bot has admin, can see everything
      assert Helpers.channel_viewable?("ch1")
    end
  end

  describe "channel_manageable?" do
    test "returns true when bot can manage the channel" do
      assert Helpers.channel_manageable?("ch1")
    end
  end

  describe "message_deletable?" do
    test "returns true for bot's own message" do
      assert Helpers.message_deletable?("ch1", "msg2")
    end

    test "returns true when bot has manage_messages" do
      # bot has admin
      assert Helpers.message_deletable?("ch1", "msg1")
    end

    test "returns false for unknown message" do
      refute Helpers.message_deletable?("ch1", "nonexistent")
    end
  end

  describe "message_url" do
    test "returns the correct jump URL" do
      url = Helpers.message_url("guild1", "ch1", "msg1")
      assert url == "https://discord.com/channels/guild1/ch1/msg1"
    end
  end
end
