defmodule Lingo.Integration.ChannelTest do
  @moduledoc false
  use Lingo.IntegrationCase

  setup do
    guild_id = System.get_env("GUILD_ID")
    if is_nil(guild_id) or guild_id == "", do: raise("GUILD_ID not set")

    {:ok, channel} =
      Lingo.Api.Guild.create_channel(guild_id, %{
        name: "lingo-test-#{:rand.uniform(99999)}",
        type: 0
      })

    on_exit(fn -> Lingo.Api.Channel.delete(channel.id) end)

    %{guild_id: guild_id, channel_id: channel.id, channel: channel}
  end

  describe "create channel" do
    test "setup created a valid text channel", %{channel: channel, guild_id: guild_id} do
      assert is_binary(channel.id)
      assert channel.type == :guild_text
      assert channel.guild_id == guild_id
      assert String.starts_with?(channel.name, "lingo-test-")
    end
  end

  describe "get channel" do
    test "returns the channel by ID", %{channel_id: channel_id} do
      assert {:ok, channel} = Lingo.Api.Channel.get(channel_id)
      assert channel.id == channel_id
      assert channel.type == :guild_text
      assert is_binary(channel.name)
    end
  end

  describe "modify channel" do
    test "renames the channel", %{channel_id: channel_id} do
      new_name = "renamed-#{:rand.uniform(99999)}"

      assert {:ok, channel} = Lingo.Api.Channel.modify(channel_id, %{name: new_name})
      assert channel.id == channel_id
      assert channel.name == new_name
    end
  end

  describe "permission overwrites" do
    test "edit and delete a role permission overwrite", %{
      channel_id: channel_id,
      guild_id: guild_id
    } do
      # guild_id doubles as the @everyone role ID
      assert :ok =
               Lingo.Api.Channel.edit_permissions(channel_id, guild_id, %{
                 allow: "1024",
                 deny: "0",
                 type: 0
               })

      # verify the overwrite was applied
      {:ok, channel} = Lingo.Api.Channel.get(channel_id)

      overwrite = Enum.find(channel.permission_overwrites, &(&1.id == guild_id))
      assert overwrite != nil
      assert overwrite.type == :role

      # remove the overwrite
      assert :ok = Lingo.Api.Channel.delete_permission(channel_id, guild_id)

      # verify removal
      {:ok, channel} = Lingo.Api.Channel.get(channel_id)
      refute Enum.any?(channel.permission_overwrites, &(&1.id == guild_id))
    end
  end

  describe "invites" do
    test "get_invites returns empty list initially", %{channel_id: channel_id} do
      assert {:ok, invites} = Lingo.Api.Channel.get_invites(channel_id)
      assert invites == []
    end

    test "create, get, and delete an invite", %{channel_id: channel_id} do
      assert {:ok, invite} =
               Lingo.Api.Channel.create_invite(channel_id, %{max_age: 300})

      assert is_binary(invite.code)
      assert invite.max_age == 300

      # get the invite
      assert {:ok, fetched} = Lingo.Api.Invite.get(invite.code)
      assert fetched.code == invite.code

      # delete it
      assert {:ok, deleted} = Lingo.Api.Invite.delete(invite.code)
      assert deleted.code == invite.code
    end
  end

  describe "typing indicator" do
    test "trigger_typing returns :ok", %{channel_id: channel_id} do
      assert :ok = Lingo.Api.Channel.trigger_typing(channel_id)
    end
  end

  describe "voice channel status" do
    test "sets and clears status on a voice channel", %{guild_id: guild_id} do
      {:ok, voice_channel} =
        Lingo.Api.Guild.create_channel(guild_id, %{
          name: "lingo-voice-status-#{:rand.uniform(99999)}",
          type: 2
        })

      on_exit(fn -> Lingo.Api.Channel.delete(voice_channel.id) end)

      assert voice_channel.type == :guild_voice

      status = "Lingo status #{:rand.uniform(99999)}"

      assert :ok = Lingo.set_voice_channel_status(voice_channel.id, %{status: status})
      assert :ok = Lingo.set_voice_channel_status(voice_channel.id, %{status: nil})
    end
  end

  describe "pinned messages" do
    test "get_pinned_messages returns empty result initially", %{channel_id: channel_id} do
      assert {:ok, pins} = Lingo.Api.Channel.get_pinned_messages(channel_id)
      assert pins.items == []
      assert pins.has_more == false
    end

    test "pin, verify, and unpin a message", %{channel_id: channel_id} do
      {:ok, message} = Lingo.Api.Message.create(channel_id, %{content: "pin test"})
      assert is_binary(message.id)

      # pin the message
      assert :ok = Lingo.Api.Channel.pin_message(channel_id, message.id)

      # verify it appears in pinned messages
      assert {:ok, pins} = Lingo.Api.Channel.get_pinned_messages(channel_id, limit: 1)
      assert length(pins.items) == 1

      [pin] = pins.items
      assert is_binary(pin.pinned_at)
      assert %Lingo.Type.Message{} = pin.message
      assert pin.message.id == message.id
      assert pin.message.pinned == true

      # unpin the message
      assert :ok = Lingo.Api.Channel.unpin_message(channel_id, message.id)

      # verify removal
      assert {:ok, pins} = Lingo.Api.Channel.get_pinned_messages(channel_id)
      assert pins.items == []
    end
  end

  describe "delete channel" do
    test "deletes a separate temporary channel", %{guild_id: guild_id} do
      {:ok, temp} =
        Lingo.Api.Guild.create_channel(guild_id, %{
          name: "lingo-delete-test-#{:rand.uniform(99999)}",
          type: 0
        })

      assert {:ok, deleted} = Lingo.Api.Channel.delete(temp.id)
      assert deleted.id == temp.id

      # confirm it no longer exists
      assert {:error, {404, _}} = Lingo.Api.Channel.get(temp.id)
    end
  end
end
