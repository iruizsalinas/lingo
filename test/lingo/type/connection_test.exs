defmodule Lingo.Type.ConnectionTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.{Connection, Integration}

  test "parses a connection with its partial guild integrations" do
    connection =
      Connection.new(%{
        "id" => "1",
        "name" => "me",
        "type" => "twitch",
        "verified" => true,
        "visibility" => 1,
        "integrations" => [%{"id" => "i1", "name" => "Subs", "type" => "twitch"}]
      })

    assert %Connection{
             type: "twitch",
             verified: true,
             visibility: :everyone,
             integrations: [%Integration{id: "i1", name: "Subs", type: "twitch"}]
           } = connection

    assert %Connection{integrations: []} = Connection.new(%{"id" => "2"})
  end
end
