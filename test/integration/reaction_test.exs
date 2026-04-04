defmodule Lingo.Integration.ReactionTest do
  @moduledoc false
  use Lingo.IntegrationCase

  setup do
    guild_id = System.get_env("GUILD_ID")
    if is_nil(guild_id) or guild_id == "", do: raise("GUILD_ID not set")

    {:ok, me} = Lingo.Api.User.get_current()

    {:ok, channel} =
      Lingo.Api.Guild.create_channel(guild_id, %{
        name: "lingo-react-test-#{:rand.uniform(99999)}",
        type: 0
      })

    {:ok, msg} = Lingo.Api.Message.create(channel.id, %{content: "reaction test"})

    on_exit(fn -> Lingo.Api.Channel.delete(channel.id) end)

    %{channel_id: channel.id, message_id: msg.id, bot_id: me.id}
  end

  describe "create/3" do
    test "adds a unicode reaction", %{channel_id: cid, message_id: mid} do
      assert :ok = Lingo.Api.Reaction.create(cid, mid, "\u{1F44D}")
    end
  end

  describe "get_users/3" do
    test "lists users who reacted, including the bot", %{
      channel_id: cid,
      message_id: mid,
      bot_id: bot_id
    } do
      :ok = Lingo.Api.Reaction.create(cid, mid, "\u{1F44D}")

      assert {:ok, users} = Lingo.Api.Reaction.get_users(cid, mid, "\u{1F44D}")
      assert is_list(users)
      assert Enum.any?(users, &(&1.id == bot_id))
    end
  end

  describe "delete_own/3" do
    test "removes the bot's own reaction", %{channel_id: cid, message_id: mid} do
      :ok = Lingo.Api.Reaction.create(cid, mid, "\u{1F44D}")

      assert :ok = Lingo.Api.Reaction.delete_own(cid, mid, "\u{1F44D}")

      assert {:ok, users} = Lingo.Api.Reaction.get_users(cid, mid, "\u{1F44D}")
      assert users == []
    end
  end

  describe "delete_all_for_emoji/3" do
    test "removes all reactions for a specific emoji", %{channel_id: cid, message_id: mid} do
      :ok = Lingo.Api.Reaction.create(cid, mid, "\u{1F44D}")

      assert :ok = Lingo.Api.Reaction.delete_all_for_emoji(cid, mid, "\u{1F44D}")

      assert {:ok, users} = Lingo.Api.Reaction.get_users(cid, mid, "\u{1F44D}")
      assert users == []
    end
  end

  describe "delete_all/2" do
    test "clears all reactions from a message", %{channel_id: cid, message_id: mid} do
      :ok = Lingo.Api.Reaction.create(cid, mid, "\u{1F44D}")
      :ok = Lingo.Api.Reaction.create(cid, mid, "\u{2764}\u{FE0F}")

      assert :ok = Lingo.Api.Reaction.delete_all(cid, mid)

      assert {:ok, []} = Lingo.Api.Reaction.get_users(cid, mid, "\u{1F44D}")
      assert {:ok, []} = Lingo.Api.Reaction.get_users(cid, mid, "\u{2764}\u{FE0F}")
    end
  end

  describe "get_users/4 with limit" do
    test "respects the limit option", %{channel_id: cid, message_id: mid} do
      :ok = Lingo.Api.Reaction.create(cid, mid, "\u{1F44D}")

      assert {:ok, users} = Lingo.Api.Reaction.get_users(cid, mid, "\u{1F44D}", limit: 1)
      assert length(users) <= 1
    end
  end

  describe "delete_user/4" do
    test "removes a reaction by user ID", %{
      channel_id: cid,
      message_id: mid,
      bot_id: bot_id
    } do
      :ok = Lingo.Api.Reaction.create(cid, mid, "\u{1F44D}")

      assert :ok = Lingo.Api.Reaction.delete_user(cid, mid, "\u{1F44D}", bot_id)

      assert {:ok, users} = Lingo.Api.Reaction.get_users(cid, mid, "\u{1F44D}")
      refute Enum.any?(users, &(&1.id == bot_id))
    end
  end
end
