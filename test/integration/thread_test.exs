defmodule Lingo.Integration.ThreadTest do
  @moduledoc false
  use Lingo.IntegrationCase

  setup do
    guild_id = System.get_env("GUILD_ID")
    if is_nil(guild_id) or guild_id == "", do: raise("GUILD_ID not set")

    {:ok, me} = Lingo.Api.User.get_current()

    {:ok, channel} =
      Lingo.Api.Guild.create_channel(guild_id, %{
        name: "lingo-thread-test-#{:rand.uniform(99999)}",
        type: 0
      })

    {:ok, msg} = Lingo.Api.Message.create(channel.id, %{content: "thread parent"})

    on_exit(fn -> Lingo.Api.Channel.delete(channel.id) end)

    %{guild_id: guild_id, channel_id: channel.id, message_id: msg.id, bot_id: me.id}
  end

  describe "start_without_message/2" do
    test "creates a public thread", %{channel_id: channel_id} do
      assert {:ok, thread} =
               Lingo.Api.Thread.start_without_message(channel_id, %{name: "test-thread", type: 11})

      assert is_binary(thread.id)
      assert thread.name == "test-thread"
    end
  end

  describe "start_from_message/3" do
    test "creates a thread from a message", %{channel_id: channel_id, message_id: message_id} do
      assert {:ok, thread} =
               Lingo.Api.Thread.start_from_message(channel_id, message_id, %{name: "msg-thread"})

      assert is_binary(thread.id)
      assert thread.name == "msg-thread"
    end
  end

  describe "join/1" do
    test "joins a thread", %{channel_id: channel_id} do
      {:ok, thread} =
        Lingo.Api.Thread.start_without_message(channel_id, %{name: "join-thread", type: 11})

      assert :ok = Lingo.Api.Thread.leave(thread.id)
      assert :ok = Lingo.Api.Thread.join(thread.id)
    end
  end

  describe "get_member/3" do
    test "returns thread member with member data", %{channel_id: channel_id, bot_id: bot_id} do
      {:ok, thread} =
        Lingo.Api.Thread.start_without_message(channel_id, %{name: "get-member-thread", type: 11})

      assert {:ok, member} = Lingo.Api.Thread.get_member(thread.id, bot_id, with_member: true)
      assert is_map(member)
    end
  end

  describe "list_members/1" do
    test "returns a list of thread members", %{channel_id: channel_id} do
      {:ok, thread} =
        Lingo.Api.Thread.start_without_message(channel_id, %{
          name: "list-members-thread",
          type: 11
        })

      assert {:ok, members} = Lingo.Api.Thread.list_members(thread.id)
      assert is_list(members)
      assert length(members) >= 1
    end
  end

  describe "leave/1" do
    test "leaves a thread", %{channel_id: channel_id} do
      {:ok, thread} =
        Lingo.Api.Thread.start_without_message(channel_id, %{name: "leave-thread", type: 11})

      assert :ok = Lingo.Api.Thread.leave(thread.id)
    end
  end

  describe "add_member/2" do
    test "re-adds the bot to a thread", %{channel_id: channel_id, bot_id: bot_id} do
      {:ok, thread} =
        Lingo.Api.Thread.start_without_message(channel_id, %{name: "add-member-thread", type: 11})

      :ok = Lingo.Api.Thread.leave(thread.id)
      assert :ok = Lingo.Api.Thread.add_member(thread.id, bot_id)
    end
  end

  describe "remove_member/2" do
    test "removes the bot from a thread", %{channel_id: channel_id, bot_id: bot_id} do
      {:ok, thread} =
        Lingo.Api.Thread.start_without_message(channel_id, %{
          name: "remove-member-thread",
          type: 11
        })

      assert :ok = Lingo.Api.Thread.remove_member(thread.id, bot_id)
    end
  end

  describe "list_public_archived/1" do
    test "returns archived public threads", %{channel_id: channel_id} do
      {:ok, thread} =
        Lingo.Api.Thread.start_without_message(channel_id, %{
          name: "archive-public-thread",
          type: 11
        })

      {:ok, _} = Lingo.Api.Channel.modify(thread.id, %{archived: true})

      assert {:ok, result} = Lingo.Api.Thread.list_public_archived(channel_id)
      assert is_map(result)
    end
  end

  describe "list_private_archived/1" do
    test "returns archived private threads", %{channel_id: channel_id} do
      {:ok, thread} =
        Lingo.Api.Thread.start_without_message(channel_id, %{
          name: "archive-private-thread",
          type: 12
        })

      {:ok, _} = Lingo.Api.Channel.modify(thread.id, %{archived: true})

      assert {:ok, result} = Lingo.Api.Thread.list_private_archived(channel_id)
      assert is_map(result)
    end
  end

  describe "list_joined_private_archived/1" do
    test "returns joined private archived threads", %{channel_id: channel_id} do
      {:ok, thread} =
        Lingo.Api.Thread.start_without_message(channel_id, %{
          name: "joined-archived-thread",
          type: 12
        })

      {:ok, _} = Lingo.Api.Channel.modify(thread.id, %{archived: true})

      assert {:ok, result} = Lingo.Api.Thread.list_joined_private_archived(channel_id)
      assert is_map(result)
    end
  end
end
