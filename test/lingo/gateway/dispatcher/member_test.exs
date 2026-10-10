defmodule Lingo.Gateway.Dispatcher.MemberTest do
  use ExUnit.Case, async: true

  alias Lingo.Gateway.Dispatcher
  alias Lingo.Type.{Member, Presence, Role}

  defmodule DispatchBot do
    use Lingo.Bot

    @impl true
    def handle_event(event, data), do: send(Lingo.Instance.get(:test_pid), {event, data})
  end

  setup do
    %{
      bot:
        Lingo.TestBot.start(
          bot: DispatchBot,
          test_pid: self(),
          start: [:cache, :collector],
          cache: [
            guilds: true,
            channels: true,
            roles: true,
            users: true,
            members: true,
            messages: true,
            presences: true
          ]
        )
    }
  end

  test "dispatches guild role create with guild_id intact" do
    Dispatcher.dispatch(:guild_role_create, %{
      "guild_id" => "guild1",
      "role" => %{
        "id" => "role1",
        "name" => "Admin",
        "permissions" => "0"
      }
    })

    assert_receive {:guild_role_create, %Role{} = role}

    assert role.id == "role1"
    assert role.guild_id == "guild1"
    assert role.name == "Admin"
  end

  test "dispatches guild role update with guild_id intact" do
    Dispatcher.dispatch(:guild_role_update, %{
      "guild_id" => "guild1",
      "role" => %{
        "id" => "role1",
        "name" => "Admin",
        "permissions" => "0"
      }
    })

    assert_receive {:guild_role_update, %{old: nil, new: %Role{} = role}}

    assert role.id == "role1"
    assert role.guild_id == "guild1"
    assert role.name == "Admin"
  end

  test "dispatches guild members chunk with member and presence context intact" do
    Dispatcher.dispatch(:guild_members_chunk, %{
      "guild_id" => "guild1",
      "members" => [
        %{
          "user" => %{"id" => "user1", "username" => "alice", "discriminator" => "0"},
          "roles" => ["role1"],
          "joined_at" => "2026-01-01T00:00:00Z"
        }
      ],
      "presences" => [
        %{
          "user" => %{"id" => "user1", "username" => "alice", "discriminator" => "0"},
          "status" => "online",
          "activities" => []
        }
      ],
      "chunk_index" => 0,
      "chunk_count" => 1,
      "nonce" => "nonce1"
    })

    assert_receive {:guild_members_chunk,
                    %{
                      guild_id: "guild1",
                      members: [%Member{} = member],
                      presences: [%Presence{} = presence],
                      chunk_index: 0,
                      chunk_count: 1,
                      nonce: "nonce1"
                    }}

    assert member.guild_id == "guild1"
    assert member.user.id == "user1"
    assert presence.guild_id == "guild1"
    assert presence.user.id == "user1"
    assert presence.status == :online

    assert %Member{user: %{id: "user1"}, guild_id: "guild1"} =
             Lingo.Cache.Member.get("guild1", "user1")

    assert %Presence{user: %{id: "user1"}, guild_id: "guild1"} =
             Lingo.Cache.Presence.get("guild1", "user1")
  end

  test "dispatches presence update with cached user details when payload user is partial" do
    Lingo.Cache.Store.put_user(%Lingo.Type.User{id: "user1", username: "alice", bot: true})

    Dispatcher.dispatch(:presence_update, %{
      "guild_id" => "guild1",
      "user" => %{"id" => "user1"},
      "status" => "idle",
      "activities" => []
    })

    assert_receive {:presence_update, %{old: nil, new: %Presence{} = presence}}

    assert presence.guild_id == "guild1"
    assert presence.status == :idle
    assert presence.user.username == "alice"
    assert presence.user.bot == true
  end
end
