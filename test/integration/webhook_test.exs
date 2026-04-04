defmodule Lingo.Integration.WebhookTest do
  @moduledoc false
  use Lingo.IntegrationCase

  setup do
    guild_id = System.get_env("GUILD_ID")
    if is_nil(guild_id) or guild_id == "", do: raise("GUILD_ID not set")

    {:ok, channel} =
      Lingo.Api.Guild.create_channel(guild_id, %{
        name: "lingo-wh-test-#{:rand.uniform(99999)}",
        type: 0
      })

    {:ok, webhook} = Lingo.Api.Webhook.create(channel.id, %{name: "lingo-test-hook"})

    on_exit(fn -> Lingo.Api.Channel.delete(channel.id) end)

    %{
      guild_id: guild_id,
      channel_id: channel.id,
      webhook_id: webhook.id,
      webhook_token: webhook.token
    }
  end

  describe "create/2" do
    test "setup created a valid webhook", %{
      webhook_id: webhook_id,
      webhook_token: webhook_token,
      channel_id: channel_id
    } do
      assert is_binary(webhook_id)
      assert is_binary(webhook_token)

      {:ok, wh} = Lingo.Api.Webhook.get(webhook_id)
      assert wh.name == "lingo-test-hook"
      assert wh.channel_id == channel_id
      assert wh.type == :incoming
    end
  end

  describe "get/1" do
    test "returns the webhook by ID", %{webhook_id: webhook_id} do
      assert {:ok, wh} = Lingo.Api.Webhook.get(webhook_id)
      assert wh.id == webhook_id
      assert wh.name == "lingo-test-hook"
    end
  end

  describe "get_with_token/2" do
    test "returns the webhook by ID and token", %{
      webhook_id: webhook_id,
      webhook_token: webhook_token
    } do
      assert {:ok, wh} = Lingo.Api.Webhook.get_with_token(webhook_id, webhook_token)
      assert wh.id == webhook_id
      assert wh.name == "lingo-test-hook"
    end
  end

  describe "get_channel_webhooks/1" do
    test "lists webhooks for the channel", %{channel_id: channel_id, webhook_id: webhook_id} do
      assert {:ok, webhooks} = Lingo.Api.Webhook.get_channel_webhooks(channel_id)
      assert is_list(webhooks)
      assert Enum.any?(webhooks, &(&1.id == webhook_id))
    end
  end

  describe "get_guild_webhooks/1" do
    test "lists webhooks for the guild including ours", %{
      guild_id: guild_id,
      webhook_id: webhook_id
    } do
      assert {:ok, webhooks} = Lingo.Api.Webhook.get_guild_webhooks(guild_id)
      assert is_list(webhooks)
      assert Enum.any?(webhooks, &(&1.id == webhook_id))
    end
  end

  describe "modify/2" do
    test "renames the webhook", %{webhook_id: webhook_id} do
      assert {:ok, wh} = Lingo.Api.Webhook.modify(webhook_id, %{name: "renamed-hook"})
      assert wh.id == webhook_id
      assert wh.name == "renamed-hook"
    end
  end

  describe "modify_with_token/3" do
    test "renames the webhook via token auth", %{
      webhook_id: webhook_id,
      webhook_token: webhook_token
    } do
      assert {:ok, wh} =
               Lingo.Api.Webhook.modify_with_token(webhook_id, webhook_token, %{
                 name: "token-renamed"
               })

      assert wh.id == webhook_id
      assert wh.name == "token-renamed"
    end
  end

  describe "execute/4" do
    test "sends a message and returns it with wait: true", %{
      webhook_id: webhook_id,
      webhook_token: webhook_token
    } do
      assert {:ok, msg} =
               Lingo.Api.Webhook.execute(
                 webhook_id,
                 webhook_token,
                 %{
                   content: "hello from webhook"
                 }, wait: true)

      assert is_binary(msg.id)
      assert msg.content == "hello from webhook"
    end
  end

  describe "webhook message lifecycle" do
    test "get, edit, and delete a webhook message", %{
      webhook_id: webhook_id,
      webhook_token: webhook_token
    } do
      {:ok, msg} =
        Lingo.Api.Webhook.execute(
          webhook_id,
          webhook_token,
          %{
            content: "lifecycle test"
          }, wait: true)

      # get the message
      assert {:ok, fetched} = Lingo.Api.Webhook.get_message(webhook_id, webhook_token, msg.id)
      assert fetched.id == msg.id
      assert fetched.content == "lifecycle test"

      # edit the message
      assert {:ok, edited} =
               Lingo.Api.Webhook.edit_message(webhook_id, webhook_token, msg.id, %{
                 content: "edited"
               })

      assert edited.id == msg.id
      assert edited.content == "edited"

      # delete the message
      assert :ok = Lingo.Api.Webhook.delete_message(webhook_id, webhook_token, msg.id)
    end
  end

  describe "delete_with_token/2" do
    test "deletes a webhook using its token", %{channel_id: channel_id} do
      {:ok, wh2} = Lingo.Api.Webhook.create(channel_id, %{name: "lingo-delete-token-hook"})

      assert :ok = Lingo.Api.Webhook.delete_with_token(wh2.id, wh2.token)
      assert {:error, {404, _}} = Lingo.Api.Webhook.get(wh2.id)
    end
  end

  describe "delete/1" do
    test "deletes the webhook using bot auth", %{webhook_id: webhook_id} do
      assert :ok = Lingo.Api.Webhook.delete(webhook_id)
      assert {:error, {404, _}} = Lingo.Api.Webhook.get(webhook_id)
    end
  end
end
