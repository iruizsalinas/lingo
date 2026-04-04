defmodule Lingo.CDNTest do
  use ExUnit.Case, async: true

  alias Lingo.CDN

  describe "user_avatar/1" do
    test "builds URL for user with avatar" do
      url = CDN.user_avatar(%{id: "123", avatar: "abc"})
      assert url == "https://cdn.discordapp.com/avatars/123/abc.webp"
    end

    test "builds URL for animated avatar" do
      url = CDN.user_avatar(%{id: "123", avatar: "a_abc"})
      assert url == "https://cdn.discordapp.com/avatars/123/a_abc.gif"
    end

    test "falls back to default avatar when nil" do
      url = CDN.user_avatar(%{id: "123", avatar: nil})
      assert url =~ "https://cdn.discordapp.com/embed/avatars/"
      assert url =~ ".png"
    end
  end

  describe "default_avatar/1" do
    test "returns an avatar index URL" do
      url = CDN.default_avatar("123456789012345678")
      assert url =~ ~r"https://cdn.discordapp.com/embed/avatars/\d\.png"
    end

    test "index is derived from user id" do
      import Bitwise
      user_id = "80351110224678912"
      expected_index = rem(String.to_integer(user_id) >>> 22, 6)

      assert CDN.default_avatar(user_id) ==
               "https://cdn.discordapp.com/embed/avatars/#{expected_index}.png"
    end
  end

  describe "guild_icon/1" do
    test "returns nil when icon is nil" do
      assert CDN.guild_icon(%{id: "1", icon: nil}) == nil
    end

    test "builds URL when icon exists" do
      url = CDN.guild_icon(%{id: "1", icon: "iconhash"})
      assert url == "https://cdn.discordapp.com/icons/1/iconhash.webp"
    end

    test "animated icon uses gif" do
      url = CDN.guild_icon(%{id: "1", icon: "a_animated"})
      assert url == "https://cdn.discordapp.com/icons/1/a_animated.gif"
    end
  end

  describe "guild_splash/1" do
    test "returns nil when splash is nil" do
      assert CDN.guild_splash(%{id: "1", splash: nil}) == nil
    end

    test "builds URL" do
      url = CDN.guild_splash(%{id: "1", splash: "splashhash"})
      assert url =~ "/splashes/1/splashhash"
    end
  end

  describe "guild_banner/1" do
    test "returns nil when banner is nil" do
      assert CDN.guild_banner(%{id: "1", banner: nil}) == nil
    end

    test "builds URL" do
      url = CDN.guild_banner(%{id: "1", banner: "bannerhash"})
      assert url =~ "/banners/1/bannerhash"
    end
  end

  describe "emoji_url/2" do
    test "static emoji" do
      assert CDN.emoji_url("123") == "https://cdn.discordapp.com/emojis/123.png"
    end

    test "animated emoji" do
      assert CDN.emoji_url("123", true) == "https://cdn.discordapp.com/emojis/123.gif"
    end
  end

  describe "sticker_url/2" do
    test "png sticker" do
      assert CDN.sticker_url("s1", :png) =~ "/stickers/s1.png"
    end

    test "lottie sticker" do
      assert CDN.sticker_url("s1", :lottie) =~ "/stickers/s1.json"
    end

    test "gif sticker" do
      assert CDN.sticker_url("s1", :gif) =~ "/stickers/s1.gif"
    end
  end
end
