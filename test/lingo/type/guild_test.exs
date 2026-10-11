defmodule Lingo.Type.GuildTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.Guild

  describe "Guild" do
    test "parses enum fields to atoms" do
      data = %{
        "id" => "1",
        "name" => "Test",
        "owner_id" => "2",
        "verification_level" => 0,
        "default_message_notifications" => 1,
        "explicit_content_filter" => 2,
        "mfa_level" => 1,
        "nsfw_level" => 3,
        "premium_tier" => 2
      }

      guild = Guild.new(data)
      assert guild.verification_level == :none
      assert guild.default_message_notifications == :only_mentions
      assert guild.explicit_content_filter == :all_members
      assert guild.mfa_level == :elevated
      assert guild.nsfw_level == :age_restricted
      assert guild.premium_tier == :tier_2
    end

    test "parses nested roles, members, and emojis with guild context" do
      data = %{
        "id" => "1",
        "name" => "G",
        "owner_id" => "2",
        "roles" => [
          %{"id" => "r1", "name" => "Admin", "permissions" => "8"},
          %{"id" => "r2", "name" => "Member", "permissions" => "0"}
        ],
        "members" => [
          %{
            "user" => %{"id" => "u1", "username" => "alice", "discriminator" => "0"},
            "roles" => ["r1"]
          }
        ],
        "emojis" => [
          %{"id" => "e1", "name" => "happy", "animated" => true}
        ]
      }

      guild = Guild.new(data)
      assert length(guild.roles) == 2
      assert hd(guild.roles).name == "Admin"
      assert hd(guild.roles).guild_id == "1"
      assert hd(guild.members).guild_id == "1"
      assert hd(guild.members).user.id == "u1"
      assert length(guild.emojis) == 1
      assert hd(guild.emojis).animated == true
    end

    test "handles unavailable guild" do
      guild = Guild.new(%{"id" => "1", "unavailable" => true})
      assert guild.unavailable == true
      assert guild.name == nil
    end

    test "parses current optional guild fields" do
      guild =
        Guild.new(%{
          "id" => "1",
          "name" => "G",
          "owner_id" => "2",
          "welcome_screen" => %{
            "description" => "Welcome",
            "welcome_channels" => [
              %{
                "channel_id" => "c1",
                "description" => "Rules",
                "emoji_id" => nil,
                "emoji_name" => "📜"
              }
            ]
          },
          "safety_alerts_channel_id" => "alerts",
          "incidents_data" => %{
            "invites_disabled_until" => nil,
            "raid_detected_at" => "2026-10-09T11:30:00+00:00"
          }
        })

      assert %Lingo.Type.WelcomeScreen{description: "Welcome", welcome_channels: [channel]} =
               guild.welcome_screen

      assert channel == %{channel_id: "c1", description: "Rules", emoji_id: nil, emoji_name: "📜"}
      assert guild.safety_alerts_channel_id == "alerts"

      assert %Lingo.Type.IncidentsData{invites_disabled_until: nil, raid_detected_at: raid} =
               guild.incidents_data

      assert raid == ~U[2026-10-09 11:30:00Z]
    end
  end
end
