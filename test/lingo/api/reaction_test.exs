defmodule Lingo.Api.ReactionTest do
  use ExUnit.Case, async: true

  alias Lingo.Api.Reaction
  alias Lingo.Type.Emoji

  describe "encode_emoji/1" do
    test "keeps unicode emoji usable for reaction routes" do
      assert Reaction.encode_emoji("🔥") == "%F0%9F%94%A5"
    end

    test "keeps name:id custom emoji route format" do
      assert Reaction.encode_emoji("blobcat:123456789") == "blobcat:123456789"
    end

    test "normalizes static custom emoji markdown" do
      assert Reaction.encode_emoji("<:blobcat:123456789>") == "blobcat:123456789"
    end

    test "normalizes animated custom emoji markdown" do
      assert Reaction.encode_emoji("<a:blobcat:123456789>") == "blobcat:123456789"
    end

    test "does not treat malformed custom emoji markdown as a path segment" do
      assert Reaction.encode_emoji("<:bad/name:123456789>") == "%3C:bad%2Fname:123456789%3E"
    end

    test "normalizes emoji structs" do
      emoji = %Emoji{name: "blobcat", id: "123456789"}

      assert Reaction.encode_emoji(emoji) == "blobcat:123456789"
    end
  end
end
