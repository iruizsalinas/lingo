defmodule Lingo.Type.GuildWidgetTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.{Channel, GuildWidget}

  test "parses Discord's example guild widget" do
    widget =
      GuildWidget.new(%{
        "id" => "290926798626999250",
        "name" => "Test Server",
        "instant_invite" => "https://discord.com/invite/abcdefg",
        "channels" => [
          %{"id" => "705216630279993882", "name" => "elephant", "position" => 2},
          %{"id" => "669583461748992190", "name" => "groovy-music", "position" => 1}
        ],
        "members" => [
          %{
            "id" => "0",
            "username" => "1234",
            "discriminator" => "0000",
            "avatar" => nil,
            "status" => "online",
            "avatar_url" => "https://cdn.discordapp.com/widget-avatars/x/y"
          }
        ],
        "presence_count" => 1
      })

    assert %GuildWidget{
             id: "290926798626999250",
             name: "Test Server",
             instant_invite: "https://discord.com/invite/abcdefg",
             presence_count: 1,
             channels: [
               %Channel{id: "705216630279993882", name: "elephant", position: 2},
               %Channel{name: "groovy-music"}
             ],
             members: [member]
           } = widget

    assert hd(widget.channels).guild_id == "290926798626999250"

    assert member == %{
             id: "0",
             username: "1234",
             discriminator: "0000",
             avatar: nil,
             status: :online,
             avatar_url: "https://cdn.discordapp.com/widget-avatars/x/y"
           }
  end
end
