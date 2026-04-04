defmodule Lingo.Gateway.IntentsTest do
  use ExUnit.Case, async: true
  import Bitwise

  alias Lingo.Gateway.Intents

  describe "resolve/1" do
    test "combines a list of intent atoms into a bitfield" do
      result = Intents.resolve([:guilds, :guild_messages])
      assert result == bor(1 <<< 0, 1 <<< 9)
    end

    test "single intent" do
      assert Intents.resolve([:guilds]) == 1
    end

    test "passes through raw integer" do
      assert Intents.resolve(513) == 513
    end

    test "empty list returns 0" do
      assert Intents.resolve([]) == 0
    end

    test "raises on unknown intent" do
      assert_raise ArgumentError, ~r/unknown intent/, fn ->
        Intents.resolve([:fake_intent])
      end
    end

    test "all known intents resolve to a specific bitfield" do
      result = Intents.resolve(Intents.names())
      # each intent should contribute exactly one bit
      assert result == Enum.reduce(Intents.names(), 0, &bor(Intents.resolve([&1]), &2))
    end
  end

  describe "all/0" do
    test "includes all intents" do
      all = Intents.all()
      assert band(all, 1 <<< 0) != 0
      assert band(all, 1 <<< 1) != 0
      assert band(all, 1 <<< 9) != 0
      assert band(all, 1 <<< 15) != 0
    end
  end

  describe "non_privileged/0" do
    test "excludes guild_members (bit 1)" do
      result = Intents.non_privileged()
      assert band(result, 1 <<< 1) == 0
    end

    test "excludes guild_presences (bit 8)" do
      result = Intents.non_privileged()
      assert band(result, 1 <<< 8) == 0
    end

    test "excludes message_content (bit 15)" do
      result = Intents.non_privileged()
      assert band(result, 1 <<< 15) == 0
    end

    test "includes guilds (bit 0)" do
      result = Intents.non_privileged()
      assert band(result, 1 <<< 0) != 0
    end
  end

  describe "privileged?/1" do
    test "guild_members is privileged" do
      assert Intents.privileged?(:guild_members)
    end

    test "guild_presences is privileged" do
      assert Intents.privileged?(:guild_presences)
    end

    test "message_content is privileged" do
      assert Intents.privileged?(:message_content)
    end

    test "guilds is not privileged" do
      refute Intents.privileged?(:guilds)
    end

    test "guild_messages is not privileged" do
      refute Intents.privileged?(:guild_messages)
    end
  end

  describe "names/0" do
    test "returns exactly 21 intent names" do
      names = Intents.names()
      assert length(names) == 21
      assert :guilds in names
      assert :guild_messages in names
      assert :message_content in names
      assert :direct_message_polls in names
    end
  end
end
