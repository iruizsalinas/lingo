defmodule Lingo.Type.VoiceStateTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.{Member, VoiceState}

  test "parses Discord's example voice state" do
    state =
      VoiceState.new(%{
        "channel_id" => "157733188964188161",
        "user_id" => "80351110224678912",
        "session_id" => "90326bd25d71d39b9ef95b299e3872ff",
        "deaf" => false,
        "mute" => false,
        "self_deaf" => false,
        "self_mute" => true,
        "suppress" => false,
        "request_to_speak_timestamp" => "2021-03-31T18:45:31.297561+00:00"
      })

    assert %VoiceState{
             channel_id: "157733188964188161",
             user_id: "80351110224678912",
             self_mute: true,
             member: nil,
             request_to_speak_timestamp: ~U[2021-03-31 18:45:31.297561Z]
           } = state
  end

  test "the member belongs to the voice state's guild" do
    state =
      VoiceState.new(%{
        "guild_id" => "g1",
        "user_id" => "u1",
        "member" => %{"user" => %{"id" => "u1"}, "roles" => []}
      })

    assert %Member{guild_id: "g1", user: %{id: "u1"}} = state.member
  end
end
