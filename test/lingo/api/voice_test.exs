defmodule Lingo.Api.VoiceTest do
  use ExUnit.Case, async: true

  import Lingo.FakeRest, only: [respond: 1]

  alias Lingo.Api.Voice
  alias Lingo.Type.{Member, VoiceRegion, VoiceState}

  setup do
    Lingo.FakeRest.start()
    :ok
  end

  test "voice regions" do
    respond([%{"id" => "us-east", "name" => "US East", "optimal" => true}])

    assert {:ok,
            [
              %VoiceRegion{
                id: "us-east",
                name: "US East",
                optimal: true,
                deprecated: false,
                custom: false
              }
            ]} = Voice.list_regions()

    assert_received {:request, :get, "/api/v10/voice/regions", [], nil}
  end

  test "voice states belong to the guild they were fetched from" do
    respond(%{
      "channel_id" => "c1",
      "user_id" => "u1",
      "session_id" => "s",
      "member" => %{"user" => %{"id" => "u1"}, "roles" => []}
    })

    assert {:ok, %VoiceState{guild_id: "g1", user_id: "u1", member: %Member{guild_id: "g1"}}} =
             Voice.get_state("g1", "u1")

    assert_received {:request, :get, "/api/v10/guilds/g1/voice-states/u1", [], nil}

    assert {:ok, %VoiceState{guild_id: "g1"}} = Voice.get_current_state("g1")
    assert_received {:request, :get, "/api/v10/guilds/g1/voice-states/@me", [], nil}
  end
end
