defmodule Lingo.Cache.VoiceStateTest do
  use ExUnit.Case, async: true

  alias Lingo.Cache
  alias Lingo.Cache.Store
  alias Lingo.Type.VoiceState

  setup do
    %{bot: Lingo.TestBot.start(start: [:cache], cache: [voice_states: true])}
  end

  test "gets and lists who is in a guild's voice channels" do
    Store.put_voice_state("g1", %VoiceState{user_id: "u1", channel_id: "v1"})
    Store.put_voice_state("g1", %VoiceState{user_id: "u2", channel_id: "v2"})
    Store.put_voice_state("g2", %VoiceState{user_id: "u3", channel_id: "v3"})

    assert Cache.VoiceState.get("g1", "u1").channel_id == "v1"
    assert Cache.VoiceState.list("g1") |> Enum.map(& &1.user_id) |> Enum.sort() == ["u1", "u2"]
  end

  test "leaving voice removes the state" do
    Store.put_voice_state("g1", %VoiceState{user_id: "u1", channel_id: "v1"})
    Store.put_voice_state("g1", %VoiceState{user_id: "u1", channel_id: nil})
    assert Cache.VoiceState.get("g1", "u1") == nil
  end
end
