defmodule Lingo.Type.UserTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.User

  describe "User" do
    test "parses all fields" do
      data = %{
        "id" => "12345",
        "username" => "testuser",
        "discriminator" => "0",
        "global_name" => "Test User",
        "avatar" => "abc123",
        "bot" => true,
        "verified" => true,
        "email" => "test@example.com",
        "collectibles" => %{"nameplate" => %{"palette" => "cobalt"}},
        "primary_guild" => %{"identity_guild_id" => "guild1", "tag" => "TEST"},
        "public_flags" => 256
      }

      user = User.new(data)
      assert user.id == "12345"
      assert user.username == "testuser"
      assert user.global_name == "Test User"
      assert user.avatar == "abc123"
      assert user.bot == true
      assert user.verified == true
      assert user.email == "test@example.com"
      assert user.collectibles["nameplate"]["palette"] == "cobalt"
      assert user.primary_guild["tag"] == "TEST"
      assert user.public_flags == 256
    end

    test "defaults bot to false" do
      user = User.new(%{"id" => "1", "username" => "u", "discriminator" => "0"})
      assert user.bot == false
    end

    test "returns nil for nil" do
      assert User.new(nil) == nil
    end
  end
end
