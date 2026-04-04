defmodule Lingo.CacheTest do
  use ExUnit.Case

  alias Lingo.Cache
  alias Lingo.Type.{Channel, Guild, Member, Message, Role, User}

  setup do
    start_supervised!(Cache)
    :ok
  end

  describe "guild cache" do
    test "stores and retrieves a guild" do
      guild = %Guild{id: "100", name: "Test Server"}
      Cache.put_guild(guild)

      result = Cache.get_guild("100")
      assert result.id == "100"
      assert result.name == "Test Server"
    end

    test "overwrites existing guild on update" do
      Cache.put_guild(%Guild{id: "100", name: "Old Name"})
      Cache.put_guild(%Guild{id: "100", name: "New Name"})

      assert Cache.get_guild("100").name == "New Name"
    end

    test "returns nil for missing guild" do
      assert Cache.get_guild("nonexistent") == nil
    end

    test "deletes a guild" do
      Cache.put_guild(%Guild{id: "200", name: "To Delete"})
      Cache.delete_guild("200")
      assert Cache.get_guild("200") == nil
    end

    test "lists all cached guilds" do
      Cache.put_guild(%Guild{id: "1", name: "A"})
      Cache.put_guild(%Guild{id: "2", name: "B"})
      Cache.put_guild(%Guild{id: "3", name: "C"})

      ids = Cache.list_guilds() |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == ["1", "2", "3"]
    end
  end

  describe "channel cache" do
    test "stores and retrieves a channel" do
      channel = %Channel{id: "ch1", name: "general", type: :guild_text, guild_id: "g1"}
      Cache.put_channel(channel)

      result = Cache.get_channel("ch1")
      assert result.name == "general"
      assert result.guild_id == "g1"
    end

    test "deletes a channel" do
      Cache.put_channel(%Channel{id: "ch2", name: "voice", type: :guild_voice})
      Cache.delete_channel("ch2")
      assert Cache.get_channel("ch2") == nil
    end
  end

  describe "member cache" do
    test "stores and retrieves a member by guild+user" do
      member = %Member{user: %User{id: "u1", username: "alice"}, nick: "Ali", roles: ["r1"]}
      Cache.put_member("g1", member)

      result = Cache.get_member("g1", "u1")
      assert result.nick == "Ali"
      assert result.roles == ["r1"]
    end

    test "same user in different guilds are independent" do
      Cache.put_member("g1", %Member{user: %User{id: "u1", username: "alice"}, nick: "Ali"})
      Cache.put_member("g2", %Member{user: %User{id: "u1", username: "alice"}, nick: "Alice"})

      assert Cache.get_member("g1", "u1").nick == "Ali"
      assert Cache.get_member("g2", "u1").nick == "Alice"
    end

    test "deletes a member" do
      Cache.put_member("g1", %Member{user: %User{id: "u2", username: "bob"}, roles: []})
      Cache.delete_member("g1", "u2")
      assert Cache.get_member("g1", "u2") == nil
    end

    test "caching a member also caches the user" do
      Cache.put_member("g1", %Member{user: %User{id: "u3", username: "charlie"}, roles: []})
      user = Cache.get_user("u3")
      assert user.username == "charlie"
    end

    test "ignores members without a user" do
      assert Cache.put_member("g1", %Member{user: nil, roles: []}) == :ok
    end
  end

  describe "role cache" do
    test "stores and retrieves a role by guild+role" do
      role = %Role{id: "r1", name: "Admin", color: 0xFF0000}
      Cache.put_role("g1", role)

      result = Cache.get_role("g1", "r1")
      assert result.name == "Admin"
      assert result.color == 0xFF0000
    end

    test "lists roles for a guild" do
      Cache.put_role("g1", %Role{id: "r1", name: "Admin"})
      Cache.put_role("g1", %Role{id: "r2", name: "Mod"})
      Cache.put_role("g2", %Role{id: "r3", name: "Other Guild Role"})

      roles = Cache.list_roles("g1")
      names = Enum.map(roles, & &1.name) |> Enum.sort()
      assert names == ["Admin", "Mod"]
    end

    test "deletes a role" do
      Cache.put_role("g1", %Role{id: "r4", name: "Temp"})
      Cache.delete_role("g1", "r4")
      assert Cache.get_role("g1", "r4") == nil
    end
  end

  describe "message cache" do
    test "stores and retrieves a message" do
      msg = %Message{id: "m1", channel_id: "ch1", content: "hello"}
      Cache.put_message(msg)

      result = Cache.get_message("ch1", "m1")
      assert result.content == "hello"
    end

    test "deletes a message" do
      Cache.put_message(%Message{id: "m2", channel_id: "ch1", content: "bye"})
      Cache.delete_message("ch1", "m2")
      assert Cache.get_message("ch1", "m2") == nil
    end
  end

  describe "presence cache" do
    test "stores and retrieves a presence" do
      presence = %Lingo.Type.Presence{
        user: %User{id: "u1", username: "alice"},
        status: :online,
        guild_id: "g1"
      }

      Cache.put_presence("g1", presence)

      result = Cache.get_presence("g1", "u1")
      assert result.status == :online
    end

    test "ignores presences without a user" do
      assert Cache.put_presence("g1", %Lingo.Type.Presence{user: nil}) == :ok
    end
  end
end
