defmodule Lingo.Type.MessageTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.{Message, User}

  describe "Message" do
    test "parses nested author and member" do
      data = %{
        "id" => "m1",
        "channel_id" => "c1",
        "channel_type" => 0,
        "author" => %{"id" => "u1", "username" => "sender", "discriminator" => "0"},
        "member" => %{"nick" => "Snd", "roles" => ["r1"]},
        "content" => "hello world",
        "timestamp" => "2024-01-01T00:00:00Z",
        "guild_id" => "g1",
        "mentions" => [
          %{
            "id" => "u2",
            "username" => "mentioned",
            "discriminator" => "0",
            "member" => %{"nick" => "Mentioned", "roles" => ["r2"]}
          }
        ],
        "embeds" => [%{"title" => "Test"}],
        "attachments" => [
          %{
            "id" => "a1",
            "filename" => "img.png",
            "size" => 1024,
            "url" => "https://cdn/img.png",
            "proxy_url" => "https://proxy/img.png"
          }
        ],
        "reactions" => [%{"count" => 3, "emoji" => %{"name" => "👍"}}]
      }

      msg = Message.new(data)
      assert msg.channel_type == :guild_text
      assert msg.content == "hello world"
      assert msg.author.username == "sender"
      assert msg.member.nick == "Snd"
      assert msg.member.guild_id == "g1"
      assert msg.member.user.id == "u1"
      assert [%User{id: "u2"}] = msg.mentions
      assert msg.mention_members["u2"].guild_id == "g1"
      assert msg.mention_members["u2"].nick == "Mentioned"
      assert msg.mention_members["u2"].user.username == "mentioned"
      assert length(msg.embeds) == 1
      assert hd(msg.embeds).title == "Test"
      assert hd(msg.attachments).filename == "img.png"
      assert hd(msg.reactions).count == 3
    end

    test "parses current optional member fields" do
      msg =
        Message.new(%{
          "id" => "m-member",
          "channel_id" => "c1",
          "member" => %{
            "nick" => "Snd",
            "banner" => "banner_hash",
            "avatar_decoration_data" => %{"asset" => "decor"},
            "collectibles" => %{"nameplate" => %{"palette" => "teal"}},
            "roles" => []
          }
        })

      assert msg.member.banner == "banner_hash"
      assert msg.member.avatar_decoration_data["asset"] == "decor"
      assert msg.member.collectibles["nameplate"]["palette"] == "teal"
    end

    test "referenced_message recursion" do
      data = %{
        "id" => "m2",
        "channel_id" => "c1",
        "content" => "reply",
        "timestamp" => "2024-01-01T00:00:00Z",
        "referenced_message" => %{
          "id" => "m1",
          "channel_id" => "c1",
          "content" => "original",
          "timestamp" => "2024-01-01T00:00:00Z"
        }
      }

      msg = Message.new(data)
      assert msg.referenced_message.content == "original"
    end

    test "parses current optional message fields" do
      msg =
        Message.new(%{
          "id" => "m3",
          "channel_id" => "c1",
          "content" => "newer fields",
          "interaction" => %{"id" => "i1", "name" => "old interaction"},
          "role_subscription_data" => %{"role_subscription_listing_id" => "listing1"},
          "resolved" => %{"users" => %{}},
          "poll" => %{"question" => %{"text" => "Question?"}},
          "call" => %{"participants" => ["u1"], "ended_timestamp" => nil},
          "shared_client_theme" => %{"primary_color" => 123},
          "stickers" => [%{"id" => "s1"}],
          "message_snapshots" => [
            %{"message" => %{"id" => "snapshot1", "channel_id" => "c1", "content" => "snap"}},
            %{"unexpected" => true}
          ]
        })

      assert msg.interaction["id"] == "i1"
      assert msg.role_subscription_data["role_subscription_listing_id"] == "listing1"
      assert msg.resolved["users"] == %{}
      assert msg.poll["question"]["text"] == "Question?"
      assert msg.call["participants"] == ["u1"]
      assert msg.shared_client_theme["primary_color"] == 123
      assert [%{"id" => "s1"}] = msg.stickers

      assert [%{"message" => %Message{} = snapshot}, %{"unexpected" => true}] =
               msg.message_snapshots

      assert snapshot.content == "snap"
    end
  end
end
