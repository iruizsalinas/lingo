defmodule Lingo.Integration.MessageTest do
  @moduledoc false
  use Lingo.IntegrationCase

  setup do
    guild_id = System.get_env("GUILD_ID")
    if is_nil(guild_id) or guild_id == "", do: raise("GUILD_ID not set")

    {:ok, channel} =
      Lingo.Api.Guild.create_channel(guild_id, %{
        name: "lingo-msg-test-#{:rand.uniform(99999)}",
        type: 0
      })

    on_exit(fn -> Lingo.Api.Channel.delete(channel.id) end)

    %{guild_id: guild_id, channel_id: channel.id}
  end

  describe "create/2" do
    test "sends a text message", %{channel_id: channel_id} do
      assert {:ok, msg} = Lingo.Api.Message.create(channel_id, %{content: "hello"})
      assert is_binary(msg.id)
      assert msg.content == "hello"
      assert msg.channel_id == channel_id
    end

    test "sends a message with an embed", %{channel_id: channel_id} do
      embed = %{title: "Test", description: "embed"}

      assert {:ok, msg} = Lingo.Api.Message.create(channel_id, %{embeds: [embed]})
      assert is_binary(msg.id)
      assert [%Lingo.Type.Embed{title: "Test", description: "embed"} | _] = msg.embeds
    end
  end

  describe "get/2" do
    test "retrieves a message by ID", %{channel_id: channel_id} do
      {:ok, sent} = Lingo.Api.Message.create(channel_id, %{content: "fetch me"})

      assert {:ok, fetched} = Lingo.Api.Message.get(channel_id, sent.id)
      assert fetched.id == sent.id
      assert fetched.content == "fetch me"
    end
  end

  describe "list/2" do
    test "returns a list of messages", %{channel_id: channel_id} do
      {:ok, _} = Lingo.Api.Message.create(channel_id, %{content: "one"})
      {:ok, _} = Lingo.Api.Message.create(channel_id, %{content: "two"})

      assert {:ok, messages} = Lingo.Api.Message.list(channel_id)
      assert is_list(messages)
      assert length(messages) >= 2
    end

    test "respects the limit option", %{channel_id: channel_id} do
      {:ok, _} = Lingo.Api.Message.create(channel_id, %{content: "a"})
      {:ok, _} = Lingo.Api.Message.create(channel_id, %{content: "b"})

      assert {:ok, messages} = Lingo.Api.Message.list(channel_id, limit: 1)
      assert length(messages) == 1
    end
  end

  describe "edit/3" do
    test "edits message content", %{channel_id: channel_id} do
      {:ok, msg} = Lingo.Api.Message.create(channel_id, %{content: "original"})

      assert {:ok, edited} = Lingo.Api.Message.edit(channel_id, msg.id, %{content: "edited"})
      assert edited.id == msg.id
      assert edited.content == "edited"
    end
  end

  describe "delete/2" do
    test "deletes a message", %{channel_id: channel_id} do
      {:ok, msg} = Lingo.Api.Message.create(channel_id, %{content: "delete me"})

      assert :ok = Lingo.Api.Message.delete(channel_id, msg.id)
      assert {:error, {404, _}} = Lingo.Api.Message.get(channel_id, msg.id)
    end
  end

  describe "bulk_delete/3" do
    test "deletes multiple messages at once", %{channel_id: channel_id} do
      {:ok, m1} = Lingo.Api.Message.create(channel_id, %{content: "bulk 1"})
      {:ok, m2} = Lingo.Api.Message.create(channel_id, %{content: "bulk 2"})

      assert :ok = Lingo.Api.Message.bulk_delete(channel_id, [m1.id, m2.id])

      assert {:error, {404, _}} = Lingo.Api.Message.get(channel_id, m1.id)
      assert {:error, {404, _}} = Lingo.Api.Message.get(channel_id, m2.id)
    end
  end

  describe "search/2" do
    test "searches messages in a guild", %{guild_id: guild_id, channel_id: channel_id} do
      term = "unique_search_term_#{:rand.uniform(99999)}"
      {:ok, _} = Lingo.Api.Message.create(channel_id, %{content: term})

      # Discord needs time to index the message for search
      Process.sleep(2_000)

      assert {:ok, _result} = Lingo.Api.Message.search(guild_id, content: term)
    end
  end
end
