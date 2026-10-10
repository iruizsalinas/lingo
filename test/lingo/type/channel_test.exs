defmodule Lingo.Type.ChannelTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.Channel

  describe "Channel" do
    test "maps type integers to atoms" do
      types = %{
        0 => :guild_text,
        1 => :dm,
        2 => :guild_voice,
        4 => :guild_category,
        5 => :guild_announcement,
        11 => :public_thread,
        12 => :private_thread,
        13 => :guild_stage_voice,
        15 => :guild_forum
      }

      for {int, atom} <- types do
        channel = Channel.new(%{"id" => "1", "type" => int})
        assert channel.type == atom, "Expected type #{int} to map to #{atom}, got #{channel.type}"
      end
    end

    test "parses permission overwrites" do
      data = %{
        "id" => "1",
        "type" => 0,
        "permission_overwrites" => [
          %{"id" => "r1", "type" => 0, "allow" => "1024", "deny" => "0"},
          %{"id" => "u1", "type" => 1, "allow" => "0", "deny" => "2048"}
        ]
      }

      channel = Channel.new(data)
      assert length(channel.permission_overwrites) == 2
      [role_ow, member_ow] = channel.permission_overwrites
      assert role_ow.type == :role
      assert member_ow.type == :member
      assert role_ow.allow == "1024"
    end

    test "parses nested forum thread message" do
      channel =
        Channel.new(%{
          "id" => "1",
          "type" => 11,
          "message" => %{
            "id" => "m1",
            "channel_id" => "1",
            "content" => "forum starter"
          }
        })

      assert channel.message.id == "m1"
      assert channel.message.content == "forum starter"
    end

    test "parses current optional channel fields" do
      channel =
        Channel.new(%{
          "id" => "1",
          "type" => 3,
          "application_id" => "app1",
          "managed" => true,
          "member" => %{"user_id" => "u1", "join_timestamp" => "2026-01-01T00:00:00Z"},
          "default_auto_archive_duration" => 1440,
          "permissions" => "1024",
          "app_permissions" => "3072",
          "total_message_sent" => 5,
          "available_tags" => [%{"id" => "tag1", "name" => "News"}],
          "applied_tags" => ["tag1"],
          "default_reaction_emoji" => %{"emoji_name" => "wave"},
          "default_thread_rate_limit_per_user" => 10,
          "default_sort_order" => 1,
          "default_forum_layout" => 2
        })

      assert channel.application_id == "app1"
      assert channel.managed == true
      assert %Lingo.Type.ThreadMember{user_id: "u1", join_timestamp: %DateTime{}} = channel.member
      assert channel.default_auto_archive_duration == 1440
      assert channel.permissions == "1024"
      assert channel.app_permissions == "3072"
      assert channel.total_message_sent == 5
      assert [%{"id" => "tag1"}] = channel.available_tags
      assert channel.applied_tags == ["tag1"]
      assert channel.default_reaction_emoji["emoji_name"] == "wave"
      assert channel.default_thread_rate_limit_per_user == 10
      assert channel.default_sort_order == 1
      assert channel.default_forum_layout == 2
    end

    test "detects obfuscated gateway channels from the channel flag" do
      channel =
        Channel.new(%{
          "id" => "1",
          "type" => 0,
          "name" => "___hidden___",
          "flags" => 131_072
        })

      assert Channel.obfuscated?(channel)
      refute Channel.obfuscated?(%Channel{id: "2", flags: 0})
    end
  end
end
