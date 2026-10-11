defmodule Lingo.Type.ActivityInstanceTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.ActivityInstance

  test "parses Discord's example activity instance" do
    instance =
      ActivityInstance.new(%{
        "application_id" => "1215413995645968394",
        "instance_id" => "i-1276580072400224306-gc-912952092627435520-912954213460484116",
        "launch_id" => "1276580072400224306",
        "location" => %{
          "id" => "gc-912952092627435520-912954213460484116",
          "kind" => "gc",
          "channel_id" => "912954213460484116",
          "guild_id" => "912952092627435520"
        },
        "users" => ["205519959982473217"]
      })

    assert %ActivityInstance{
             application_id: "1215413995645968394",
             launch_id: "1276580072400224306",
             users: ["205519959982473217"],
             location: %{
               id: "gc-912952092627435520-912954213460484116",
               kind: :guild_channel,
               channel_id: "912954213460484116",
               guild_id: "912952092627435520"
             }
           } = instance
  end

  test "private channel locations have no guild" do
    instance = ActivityInstance.new(%{"location" => %{"kind" => "pc", "channel_id" => "1"}})
    assert %{kind: :private_channel, guild_id: nil} = instance.location
  end
end
