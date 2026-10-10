defmodule Lingo.CacheTest do
  use ExUnit.Case, async: true

  alias Lingo.Cache
  alias Lingo.Type.{Channel, Guild, Member, Role, User}

  setup do
    %{
      bot:
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
    }
  end

  describe "guild cache" do
    test "stores and retrieves a guild" do
      guild = %Guild{id: "100", name: "Test Server"}
      Lingo.Cache.Store.put_guild(guild)

      result = Cache.get_guild("100")
      assert result.id == "100"
      assert result.name == "Test Server"
    end

    test "overwrites existing guild on update" do
      Lingo.Cache.Store.put_guild(%Guild{id: "100", name: "Old Name"})
      Lingo.Cache.Store.put_guild(%Guild{id: "100", name: "New Name"})

      assert Cache.get_guild("100").name == "New Name"
    end

    test "returns nil for missing guild" do
      assert Cache.get_guild("nonexistent") == nil
    end

    test "deletes a guild" do
      Lingo.Cache.Store.put_guild(%Guild{id: "200", name: "To Delete"})
      Lingo.Cache.Store.delete_guild("200")
      assert Cache.get_guild("200") == nil
    end

    test "lists all cached guilds" do
      Lingo.Cache.Store.put_guild(%Guild{id: "1", name: "A"})
      Lingo.Cache.Store.put_guild(%Guild{id: "2", name: "B"})
      Lingo.Cache.Store.put_guild(%Guild{id: "3", name: "C"})

      ids = Cache.list_guilds() |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == ["1", "2", "3"]
    end
  end

  describe "channel cache" do
    test "stores and retrieves a channel" do
      channel = %Channel{id: "ch1", name: "general", type: :guild_text, guild_id: "g1"}
      Lingo.Cache.Store.put_channel(channel)

      result = Cache.get_channel("ch1")
      assert result.name == "general"
      assert result.guild_id == "g1"
    end

    test "deletes a channel" do
      Lingo.Cache.Store.put_channel(%Channel{id: "ch2", name: "voice", type: :guild_voice})
      Lingo.Cache.Store.delete_channel("ch2")
      assert Cache.get_channel("ch2") == nil
    end
  end

  describe "member cache" do
    test "stores and retrieves a member by guild+user" do
      member = %Member{user: %User{id: "u1", username: "alice"}, nick: "Ali", roles: ["r1"]}
      Lingo.Cache.Store.put_member("g1", member)

      result = Cache.get_member("g1", "u1")
      assert result.nick == "Ali"
      assert result.roles == ["r1"]
    end

    test "same user in different guilds are independent" do
      Lingo.Cache.Store.put_member("g1", %Member{
        user: %User{id: "u1", username: "alice"},
        nick: "Ali"
      })

      Lingo.Cache.Store.put_member("g2", %Member{
        user: %User{id: "u1", username: "alice"},
        nick: "Alice"
      })

      assert Cache.get_member("g1", "u1").nick == "Ali"
      assert Cache.get_member("g2", "u1").nick == "Alice"
    end

    test "deletes a member" do
      Lingo.Cache.Store.put_member("g1", %Member{
        user: %User{id: "u2", username: "bob"},
        roles: []
      })

      Lingo.Cache.Store.delete_member("g1", "u2")
      assert Cache.get_member("g1", "u2") == nil
    end

    test "caching a member also caches the user" do
      Lingo.Cache.Store.put_member("g1", %Member{
        user: %User{id: "u3", username: "charlie"},
        roles: []
      })

      user = Cache.get_user("u3")
      assert user.username == "charlie"
    end

    test "ignores members without a user" do
      assert Lingo.Cache.Store.put_member("g1", %Member{user: nil, roles: []}) == :ok
    end
  end

  describe "role cache" do
    test "stores and retrieves a role by guild+role" do
      role = %Role{id: "r1", name: "Admin", color: 0xFF0000}
      Lingo.Cache.Store.put_role("g1", role)

      result = Cache.get_role("g1", "r1")
      assert result.name == "Admin"
      assert result.color == 0xFF0000
    end

    test "lists roles for a guild" do
      Lingo.Cache.Store.put_role("g1", %Role{id: "r1", name: "Admin"})
      Lingo.Cache.Store.put_role("g1", %Role{id: "r2", name: "Mod"})
      Lingo.Cache.Store.put_role("g2", %Role{id: "r3", name: "Other Guild Role"})

      roles = Cache.list_roles("g1")
      names = Enum.map(roles, & &1.name) |> Enum.sort()
      assert names == ["Admin", "Mod"]
    end

    test "deletes a role" do
      Lingo.Cache.Store.put_role("g1", %Role{id: "r4", name: "Temp"})
      Lingo.Cache.Store.delete_role("g1", "r4")
      assert Cache.get_role("g1", "r4") == nil
    end
  end
end
