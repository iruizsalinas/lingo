defmodule Lingo.Cache.MergeTest do
  use ExUnit.Case, async: true

  alias Lingo.Cache
  alias Lingo.Type.{Attachment, Embed, Member, Message, Presence, User}

  setup do
    %{bot: Lingo.TestBot.start(start: [:cache])}
  end

  describe "message cache" do
    test "stores and retrieves a message" do
      msg = %Message{id: "m1", channel_id: "ch1", content: "hello"}
      Lingo.Cache.Store.put_message(msg)

      result = Cache.get_message("ch1", "m1")
      assert result.content == "hello"
    end

    test "deletes a message" do
      Lingo.Cache.Store.put_message(%Message{id: "m2", channel_id: "ch1", content: "bye"})
      Lingo.Cache.Store.delete_message("ch1", "m2")
      assert Cache.get_message("ch1", "m2") == nil
    end

    test "merges message updates through message type parsing" do
      Lingo.Cache.Store.put_message(%Message{
        id: "m3",
        channel_id: "ch1",
        content: "before",
        author: %User{id: "u1", username: "old"}
      })

      Lingo.Cache.Store.merge_message("ch1", %{
        "id" => "m3",
        "embeds" => [%{"title" => "Updated"}],
        "attachments" => [
          %{
            "id" => "a1",
            "filename" => "file.txt",
            "size" => 5,
            "url" => "https://cdn/file.txt",
            "proxy_url" => "https://proxy/file.txt"
          }
        ],
        "author" => %{"id" => "u2", "username" => "new", "discriminator" => "0"},
        "member" => %{"roles" => ["r1"], "nick" => "New"},
        "guild_id" => "g1"
      })

      result = Cache.get_message("ch1", "m3")

      assert result.content == "before"
      assert [%Embed{title: "Updated"}] = result.embeds
      assert [%Attachment{filename: "file.txt"}] = result.attachments
      assert %User{id: "u2", username: "new"} = result.author
      assert %Member{guild_id: "g1", nick: "New", user: %User{id: "u2"}} = result.member
    end

    test "merges derived message member fields with existing context" do
      Lingo.Cache.Store.put_message(%Message{
        id: "m4",
        channel_id: "ch1",
        guild_id: "g1",
        author: %User{id: "u1", username: "old", discriminator: "0"},
        member: %Member{guild_id: "g1", user: %User{id: "u1"}, nick: "Old"},
        mention_members: %{"u2" => %Member{guild_id: "g1", nick: "Before"}}
      })

      Lingo.Cache.Store.merge_message("ch1", %{
        "id" => "m4",
        "member" => %{"nick" => "Updated", "roles" => ["r1"]},
        "mentions" => [
          %{
            "id" => "u3",
            "username" => "mentioned",
            "discriminator" => "0",
            "member" => %{"nick" => "Mentioned", "roles" => ["r2"]}
          }
        ]
      })

      result = Cache.get_message("ch1", "m4")

      assert %Member{guild_id: "g1", nick: "Updated", user: %User{id: "u1"}} = result.member
      assert [%User{id: "u3"}] = result.mentions

      assert %{"u3" => %Member{guild_id: "g1", nick: "Mentioned", user: %User{id: "u3"}}} =
               result.mention_members
    end
  end

  describe "presence cache" do
    test "stores and retrieves a presence" do
      presence = %Presence{
        user: %User{id: "u1", username: "alice"},
        status: :online,
        guild_id: "g1"
      }

      Lingo.Cache.Store.put_presence("g1", presence)

      result = Cache.get_presence("g1", "u1")
      assert result.status == :online
      assert result.user.username == "alice"
      assert Cache.get_user("u1").username == "alice"
    end

    test "partial presence users do not overwrite cached user details" do
      Lingo.Cache.Store.put_user(%User{id: "u1", username: "alice", bot: true})

      Lingo.Cache.Store.put_presence("g1", %Presence{
        user: %User{id: "u1", username: "alice-renamed"},
        status: :idle,
        guild_id: "g1"
      })

      assert %User{username: "alice-renamed", bot: true} = Cache.get_user("u1")

      assert %Presence{status: :idle, user: %User{id: "u1", username: "alice-renamed", bot: true}} =
               Cache.get_presence("g1", "u1")
    end

    test "partial presence users remain addressable when no full user is cached" do
      Lingo.Cache.Store.put_presence("g1", %Presence{
        user: %User{id: "u2"},
        status: :online,
        guild_id: "g1"
      })

      assert Cache.get_user("u2") == nil
      assert %Presence{user: %User{id: "u2", username: nil}} = Cache.get_presence("g1", "u2")
    end

    test "ignores presences without a user" do
      assert Lingo.Cache.Store.put_presence("g1", %Presence{user: nil}) == :ok
    end
  end
end
