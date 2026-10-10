defmodule Lingo.Cache.MemberTest do
  use ExUnit.Case, async: true

  alias Lingo.Cache
  alias Lingo.Cache.Store
  alias Lingo.Type.{Member, User}

  setup do
    %{bot: Lingo.TestBot.start(start: [:cache], cache: [members: true, users: true])}
  end

  defp member(id, fields \\ []),
    do: struct(%Member{user: %User{id: id, username: id}, roles: []}, fields)

  test "stores and retrieves a member by guild and user" do
    Store.put_member("g1", member("u1", nick: "Ali", roles: ["r1"]))
    assert %Member{nick: "Ali", roles: ["r1"]} = Cache.Member.get("g1", "u1")
  end

  test "the same user in different guilds is independent" do
    Store.put_member("g1", member("u1", nick: "Ali"))
    Store.put_member("g2", member("u1", nick: "Alice"))

    assert Cache.Member.get("g1", "u1").nick == "Ali"
    assert Cache.Member.get("g2", "u1").nick == "Alice"
  end

  test "deletes a member" do
    Store.put_member("g1", member("u2"))
    Store.delete_member("g1", "u2")
    assert Cache.Member.get("g1", "u2") == nil
  end

  test "caching a member also caches the user" do
    Store.put_member("g1", member("u3"))
    assert Cache.User.get("u3").username == "u3"
  end

  test "ignores members without a user" do
    assert Store.put_member("g1", %Member{user: nil, roles: []}) == :ok
  end

  test "lists a guild's members, with their latest users" do
    Store.put_member("g1", member("u1"))
    Store.put_member("g1", member("u2"))
    Store.put_member("g2", member("u3"))
    Store.put_user(%User{id: "u1", username: "renamed"})

    members = Cache.Member.list("g1") |> Enum.sort_by(& &1.user.id)
    assert Enum.map(members, & &1.user.username) == ["renamed", "u2"]
  end
end
