defmodule Lingo.Type.LobbyTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.{Channel, Lobby, LobbyMember, LobbyMessage}

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

  test "members carry their additional name" do
    member =
      LobbyMember.new(%{
        "id" => "41771983429993000",
        "metadata" => nil,
        "flags" => 1,
        "additional_name" => "Twindly Shimmerleaf"
      })

    assert %LobbyMember{additional_name: "Twindly Shimmerleaf", flags: 1} = member
  end

  test "messages carry the author's lobby name and moderation metadata" do
    message =
      LobbyMessage.new(%{
        "id" => "m1",
        "type" => 0,
        "content" => "gg",
        "lobby_id" => "l1",
        "channel_id" => "l1",
        "author" => %{"id" => "u1"},
        "lobby_member" => %{"additional_name" => "Twindly"},
        "metadata" => nil,
        "moderation_metadata" => %{"flagged" => "false"},
        "flags" => 0,
        "application_id" => "a1"
      })

    assert %LobbyMessage{
             lobby_member: %{additional_name: "Twindly"},
             moderation_metadata: %{"flagged" => "false"}
           } = message

    assert %LobbyMessage{lobby_member: nil, moderation_metadata: nil} =
             LobbyMessage.new(%{"id" => "m2"})
  end
end
