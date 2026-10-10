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
      assert url == "https://cdn.discordapp.com/avatars/123/a_abc.webp?animated=true"
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

    test "legacy discriminators use discriminator % 5" do
      assert CDN.default_avatar("80351110224678912", "1337") ==
               "https://cdn.discordapp.com/embed/avatars/2.png"

      assert CDN.user_avatar(%{id: "80351110224678912", avatar: nil, discriminator: "1337"}) ==
               "https://cdn.discordapp.com/embed/avatars/2.png"
    end

    test "migrated users with discriminator 0 use the user id" do
      import Bitwise
      user_id = "80351110224678912"
      expected_index = rem(String.to_integer(user_id) >>> 22, 6)

      assert CDN.user_avatar(%{id: user_id, avatar: nil, discriminator: "0"}) ==
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

    test "animated icon uses animated webp, or the format asked for" do
      url = CDN.guild_icon(%{id: "1", icon: "a_animated"})
      assert url == "https://cdn.discordapp.com/icons/1/a_animated.webp?animated=true"

      assert CDN.guild_icon(%{id: "1", icon: "a_animated"}, format: :gif, size: 64) ==
               "https://cdn.discordapp.com/icons/1/a_animated.gif?size=64"
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

  describe "emoji/2" do
    test "static emoji" do
      assert CDN.emoji("123") == "https://cdn.discordapp.com/emojis/123.webp"
    end

    test "animated emoji" do
      assert CDN.emoji("123", true) == "https://cdn.discordapp.com/emojis/123.webp?animated=true"
    end
  end

  describe "sticker/2" do
    test "png sticker" do
      assert CDN.sticker("s1", :png) =~ "/stickers/s1.png"
    end

    test "lottie sticker" do
      assert CDN.sticker("s1", :lottie) =~ "/stickers/s1.json"
    end

    test "gif sticker" do
      assert CDN.sticker("s1", :gif) =~ "/stickers/s1.gif"
    end
  end

  describe "role_icon/1 and scheduled_event_cover/1" do
    test "build URLs from the struct's id and hash" do
      assert CDN.role_icon(%{id: "r1", icon: "h"}) ==
               "https://cdn.discordapp.com/role-icons/r1/h.webp"

      assert CDN.scheduled_event_cover(%{id: "e1", image: "a_h"}) ==
               "https://cdn.discordapp.com/guild-events/e1/a_h.webp?animated=true"
    end

    test "return nil without an image" do
      assert CDN.role_icon(%{id: "r1", icon: nil}) == nil
      assert CDN.scheduled_event_cover(%{id: "e1", image: nil}) == nil
    end
  end

  describe "options" do
    test "size and format apply to any image" do
      assert CDN.user_avatar(%{id: "1", avatar: "h"}, size: 256, format: :png) ==
               "https://cdn.discordapp.com/avatars/1/h.png?size=256"
    end
  end

  describe "member images" do
    test "avatar and banner use the member's guild" do
      member = %{guild_id: "g", user: %{id: "u"}, avatar: "a", banner: "a_b"}

      assert CDN.member_avatar(member) ==
               "https://cdn.discordapp.com/guilds/g/users/u/avatars/a.webp"

      assert CDN.member_banner(member) ==
               "https://cdn.discordapp.com/guilds/g/users/u/banners/a_b.webp?animated=true"
    end

    test "nil without a hash, user or guild" do
      assert CDN.member_banner(%{guild_id: "g", user: %{id: "u"}, banner: nil}) == nil
      assert CDN.member_avatar(%{guild_id: "g", user: nil, avatar: "a"}) == nil
      assert CDN.member_avatar(%{guild_id: nil, user: %{id: "u"}, avatar: "a"}) == nil
    end
  end

  describe "decorations, tags and sounds" do
    test "avatar decoration" do
      assert CDN.avatar_decoration(%{avatar_decoration_data: %{"asset" => "x", "sku_id" => "1"}}) ==
               "https://cdn.discordapp.com/avatar-decoration-presets/x.png"

      assert CDN.avatar_decoration(%{avatar_decoration_data: nil}) == nil
    end

    test "guild tag badge" do
      user = %{primary_guild: %{"identity_guild_id" => "g", "badge" => "b", "tag" => "LING"}}
      assert CDN.guild_tag_badge(user) == "https://cdn.discordapp.com/guild-tag-badges/g/b.png"
      assert CDN.guild_tag_badge(%{primary_guild: nil}) == nil
    end

    test "soundboard sound" do
      assert CDN.soundboard_sound("s1") == "https://cdn.discordapp.com/soundboard-sounds/s1"
    end
  end
end
