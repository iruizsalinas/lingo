defmodule Lingo.FormatTest do
  use ExUnit.Case, async: true

  alias Lingo.Format

  test "timestamp/2 takes a DateTime or Unix seconds" do
    assert Format.timestamp(1_767_225_600, :relative) == "<t:1767225600:R>"
    assert Format.timestamp(DateTime.from_unix!(1_767_225_600)) == "<t:1767225600:f>"
  end

  test "mentions" do
    assert Format.mention_user("1") == "<@1>"
    assert Format.mention_channel("2") == "<#2>"
    assert Format.mention_role("3") == "<@&3>"
  end

  describe "message_url/3" do
    test "links a guild message" do
      assert Format.message_url("guild1", "ch1", "msg1") ==
               "https://discord.com/channels/guild1/ch1/msg1"
    end

    test "uses @me for DMs" do
      assert Format.message_url(nil, "dm1", "msg1") ==
               "https://discord.com/channels/@me/dm1/msg1"
    end
  end
end
