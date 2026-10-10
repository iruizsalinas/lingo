defmodule Lingo.Helper.ChannelTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.{Channel, Guild, Member, Message, Role, User}

  setup do
    Lingo.TestBot.start(start: [:cache])

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

  describe "permissions_for" do
    test "computes effective permissions in a channel" do
      perms = Lingo.Helper.Channel.permissions_for("ch1", "user1")
      # user1 has role_mid which is allowed view_channel (1024) in ch1
      assert Lingo.Permissions.has?(perms, :view_channel)
    end

    test "returns 0 for unknown channel" do
      assert Lingo.Helper.Channel.permissions_for("nonexistent", "user1") == 0
    end
  end

  describe "channel_viewable?" do
    test "returns true when bot can see the channel" do
      # bot has admin, can see everything
      assert Lingo.Helper.Channel.viewable?("ch1")
    end
  end

  describe "channel_manageable?" do
    test "returns true when bot can manage the channel" do
      assert Lingo.Helper.Channel.manageable?("ch1")
    end
  end

  describe "message_deletable?" do
    test "returns true for bot's own message" do
      assert Lingo.Helper.Channel.message_deletable?("ch1", "msg2")
    end

    test "returns true when bot has manage_messages" do
      # bot has admin
      assert Lingo.Helper.Channel.message_deletable?("ch1", "msg1")
    end

    test "returns false for unknown message" do
      refute Lingo.Helper.Channel.message_deletable?("ch1", "nonexistent")
    end
  end
end
