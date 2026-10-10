defmodule Lingo.Type.LobbyTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.{Channel, Lobby, LobbyMember}

  test "parses a lobby with its members and linked channel" do
    lobby =
      Lobby.new(%{
        "id" => "1",
        "application_id" => "200",
        "metadata" => %{"mode" => "duo"},
        "members" => [%{"id" => "30", "flags" => 1}, %{"id" => "31", "metadata" => nil}],
        "linked_channel" => %{"id" => "10", "type" => 0}
      })

    assert %Lobby{id: "1", metadata: %{"mode" => "duo"}, linked_channel: %Channel{id: "10"}} =
             lobby

    assert [%LobbyMember{id: "30", flags: 1} = first, %LobbyMember{id: "31", flags: 0} = second] =
             lobby.members

    assert LobbyMember.can_link_lobby?(first)
    refute LobbyMember.can_link_lobby?(second)
  end

  test "a lobby without members or channel" do
    assert %Lobby{members: [], linked_channel: nil} = Lobby.new(%{"id" => "1"})
    assert Lobby.new(nil) == nil
  end
end
