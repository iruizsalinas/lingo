defmodule Lingo.Cache.PresenceTest do
  use ExUnit.Case, async: true

  alias Lingo.Cache
  alias Lingo.Cache.Store
  alias Lingo.Type.{Presence, User}

  setup do
    %{bot: Lingo.TestBot.start(start: [:cache], cache: [presences: true, users: true])}
  end

  test "gets and lists a guild's presences, with their users" do
    Store.put_presence("g1", %Presence{user: %User{id: "u1", username: "a"}, status: :online})
    Store.put_presence("g1", %Presence{user: %User{id: "u2", username: "b"}, status: :idle})
    Store.put_presence("g2", %Presence{user: %User{id: "u3", username: "c"}, status: :dnd})

    assert %Presence{status: :online, user: %User{username: "a"}} = Cache.Presence.get("g1", "u1")
    assert Cache.Presence.list("g1") |> Enum.map(& &1.status) |> Enum.sort() == [:idle, :online]
  end
end
