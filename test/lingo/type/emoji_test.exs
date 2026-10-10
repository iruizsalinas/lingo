defmodule Lingo.Type.EmojiTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.Emoji

  describe "Emoji" do
    test "format for unicode emoji" do
      emoji = %Emoji{id: nil, name: "👍"}
      assert Emoji.format(emoji) == "👍"
    end

    test "format for custom emoji" do
      emoji = %Emoji{id: "123", name: "custom"}
      assert Emoji.format(emoji) == "<:custom:123>"
    end

    test "format for animated custom emoji" do
      emoji = %Emoji{id: "456", name: "dance", animated: true}
      assert Emoji.format(emoji) == "<a:dance:456>"
    end
  end
end
