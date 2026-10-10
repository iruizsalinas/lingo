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
    assert Format.mention_command("role add", "4") == "</role add:4>"
  end

  test "emoji/1 writes unicode, custom and animated emojis" do
    assert Format.emoji(%Lingo.Type.Emoji{id: nil, name: "🔥"}) == "🔥"
    assert Format.emoji(%Lingo.Type.Emoji{id: "1", name: "blob"}) == "<:blob:1>"
    assert Format.emoji(%Lingo.Type.Emoji{id: "1", name: "blob", animated: true}) == "<a:blob:1>"
  end

  test "escape_markdown/1 escapes inline markup and line-start blocks" do
    assert Format.escape_markdown("**bold** _x_ `c` ||s|| ~~t~~ a\\b") ==
             "\\*\\*bold\\*\\* \\_x\\_ \\`c\\` \\|\\|s\\|\\| \\~\\~t\\~\\~ a\\\\b"

    assert Format.escape_markdown("> quote\n# title\n  - item\nwell-known") ==
             "\\> quote\n\\# title\n  \\- item\nwell-known"
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
