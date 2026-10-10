defmodule Lingo.Type.ParseTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.{ApplicationCommand, CommandOption, Guild}

  describe "pass-through of values Lingo doesn't know" do
    test "component builders send explicit values as given" do
      assert Lingo.Component.Modal.text_input("t", style: 3).style == 3
      assert Lingo.Component.Modal.text_input("t", style: :short).style == 1
      assert Lingo.Component.button(custom_id: "b", disabled: false).disabled == false
      assert Lingo.Component.user_select("u", default_values: []).default_values == []
      assert Lingo.Component.default_value("1", :guild) == %{id: "1", type: "guild"}
    end

    test "unknown enum values are kept instead of replaced by a default" do
      assert ApplicationCommand.new(%{"type" => 99}).type == 99
      assert ApplicationCommand.new(%{}).type == :chat_input
      assert Guild.new(%{"verification_level" => 9}).verification_level == 9

      assert ApplicationCommand.to_payload(%ApplicationCommand{name: "x", type: 99})["type"] ==
               99

      assert CommandOption.to_payload(%CommandOption{type: 12, name: "x", description: "x"})[
               "type"
             ] == 12
    end

    test "intents and permissions accept raw bits" do
      import Bitwise
      assert Lingo.Gateway.Intents.resolve([:guilds, 1 <<< 30]) == (1 ||| 1 <<< 30)
      assert Lingo.Permissions.resolve([:kick_members, 1 <<< 60]) == (2 ||| 1 <<< 60)
    end
  end

  describe "timestamps and enums" do
    test "ISO8601 timestamps become DateTimes" do
      msg =
        Lingo.Type.Message.new(%{
          "id" => "1",
          "channel_id" => "2",
          "timestamp" => "2024-01-01T12:30:00.123000+00:00",
          "edited_timestamp" => nil
        })

      assert msg.timestamp == ~U[2024-01-01 12:30:00.123000Z]
      assert msg.edited_timestamp == nil

      member = Lingo.Type.Member.new(%{"joined_at" => "2023-05-06T07:08:09Z", "roles" => []})
      assert %DateTime{year: 2023} = member.joined_at
    end

    test "unparseable timestamps are kept as they are" do
      assert Lingo.Type.Parse.timestamp("not a date") == "not a date"
    end

    test "message and channel types become atoms, unknown ones stay numbers" do
      assert Lingo.Type.Message.new(%{"type" => 19, "channel_type" => 11}).type == :reply

      assert Lingo.Type.Message.new(%{"type" => 19, "channel_type" => 11}).channel_type ==
               :public_thread

      assert Lingo.Type.Message.new(%{}).type == :default
      assert Lingo.Type.Message.new(%{"type" => 999}).type == 999
    end

    test "channel types in builders are sent as numbers" do
      select = Lingo.Component.channel_select("c", channel_types: [:guild_voice, 13])
      assert select.channel_types == [2, 13]
    end
  end
end
