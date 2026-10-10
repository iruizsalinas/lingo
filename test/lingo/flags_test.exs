defmodule Lingo.FlagsTest do
  use ExUnit.Case, async: true
  import Bitwise

  alias Lingo.Flags

  test "has?/3 reads integer, string and nil bitfields" do
    assert Flags.has?(:message, 1 <<< 13, :is_voice_message)
    refute Flags.has?(:message, 1 <<< 13, :ephemeral)
    assert Flags.has?(:application, Integer.to_string(1 <<< 23), :application_command_badge)
    refute Flags.has?(:user, nil, :staff)
  end

  test "to_list/2 names known bits and skips unknown ones" do
    assert Flags.to_list(:user, 1 <<< 6 ||| 1 <<< 17 ||| 1 <<< 40) ==
             [:hypesquad_online_house_1, :verified_developer]
  end

  test "from_list/2 builds a bitfield" do
    assert Flags.from_list(:message, [:suppress_embeds, :suppress_notifications]) == 4100
    assert Flags.from_list(:attachment, []) == 0
  end

  test "unknown flags raise" do
    assert_raise KeyError, fn -> Flags.has?(:message, 0, :nope) end
  end
end
