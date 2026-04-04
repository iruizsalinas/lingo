defmodule Lingo.Integration.MiscApiTest do
  @moduledoc false
  use Lingo.IntegrationCase

  setup do
    guild_id = System.get_env("GUILD_ID")
    if is_nil(guild_id) or guild_id == "", do: raise("GUILD_ID not set")
    %{guild_id: guild_id, app_id: Lingo.Config.application_id()}
  end

  # -- Audit Log --

  describe "audit log" do
    test "get returns audit log with entries list", %{guild_id: guild_id} do
      assert {:ok, log} = Lingo.Api.AuditLog.get(guild_id)
      assert is_list(log.audit_log_entries)
    end
  end

  # -- Application --

  describe "application" do
    test "get_current returns application with id and name" do
      assert {:ok, data} = Lingo.Api.Application.get_current()
      assert is_binary(data["id"])
      assert is_binary(data["name"])
    end

    test "get_role_connection_metadata returns a list", %{app_id: app_id} do
      assert {:ok, list} = Lingo.Api.Application.get_role_connection_metadata(app_id)
      assert is_list(list)
    end
  end

  # -- Users --

  describe "users" do
    test "get_current returns the bot user" do
      assert {:ok, user} = Lingo.Api.User.get_current()
      assert is_binary(user.id)
      assert user.bot == true
    end

    test "get fetches the bot by its own ID" do
      {:ok, me} = Lingo.Api.User.get_current()

      assert {:ok, user} = Lingo.Api.User.get(me.id)
      assert user.id == me.id
    end

    test "get_guilds returns at least one guild" do
      assert {:ok, list} = Lingo.Api.User.get_guilds()
      assert is_list(list)
      assert length(list) >= 1
    end

    test "create_dm returns error when DMing self" do
      {:ok, me} = Lingo.Api.User.get_current()
      # Bots cannot DM themselves
      assert {:error, _} = Lingo.Api.User.create_dm(me.id)
    end
  end

  # -- Voice --

  describe "voice" do
    test "list_regions returns a non-empty list of regions" do
      assert {:ok, list} = Lingo.Api.Voice.list_regions()
      assert is_list(list)
      assert length(list) > 0

      region = hd(list)
      assert is_binary(region["id"])
      assert is_binary(region["name"])
    end
  end

  # -- Soundboard --

  describe "soundboard" do
    test "list_defaults returns default sounds" do
      assert {:ok, data} = Lingo.Api.Soundboard.list_defaults()
      assert is_list(data) or is_map(data)
    end

    test "list_guild returns guild sounds", %{guild_id: guild_id} do
      assert {:ok, data} = Lingo.Api.Soundboard.list_guild(guild_id)
      assert is_list(data) or is_map(data)
    end
  end

  # -- Stickers --

  describe "stickers" do
    test "list_packs returns sticker packs" do
      assert {:ok, data} = Lingo.Api.Sticker.list_packs()
      assert is_list(data) or is_map(data)
    end

    test "list_guild returns guild stickers (may be empty)", %{guild_id: guild_id} do
      assert {:ok, list} = Lingo.Api.Sticker.list_guild(guild_id)
      assert is_list(list)
    end
  end

  # -- Entitlements --

  describe "entitlements" do
    test "list returns entitlements (may be empty)", %{app_id: app_id} do
      assert {:ok, list} = Lingo.Api.Entitlement.list(app_id)
      assert is_list(list)
    end
  end

  # -- SKUs --

  describe "SKUs" do
    test "list returns SKUs (may be empty)", %{app_id: app_id} do
      assert {:ok, list} = Lingo.Api.SKU.list(app_id)
      assert is_list(list)
    end
  end

  # -- Polls --

  describe "polls" do
    setup %{guild_id: guild_id} do
      {:ok, channel} =
        Lingo.Api.Guild.create_channel(guild_id, %{
          name: "lingo-poll-test-#{:rand.uniform(99999)}",
          type: 0
        })

      on_exit(fn -> Lingo.Api.Channel.delete(channel.id) end)

      %{channel_id: channel.id}
    end

    test "expire ends a poll", %{channel_id: channel_id} do
      {:ok, msg} =
        Lingo.Api.Message.create(channel_id, %{
          poll: %{
            question: %{text: "Test poll"},
            answers: [
              %{poll_media: %{text: "Option A"}},
              %{poll_media: %{text: "Option B"}}
            ],
            duration: 1
          }
        })

      assert {:ok, expired} = Lingo.Api.Poll.expire(channel_id, msg.id)
      assert is_map(expired)
    end

    test "get_answer_voters returns voters for answer 1", %{channel_id: channel_id} do
      {:ok, msg} =
        Lingo.Api.Message.create(channel_id, %{
          poll: %{
            question: %{text: "Test poll"},
            answers: [
              %{poll_media: %{text: "Option A"}},
              %{poll_media: %{text: "Option B"}}
            ],
            duration: 1
          }
        })

      # Expire so the poll is finalized
      Lingo.Api.Poll.expire(channel_id, msg.id)

      assert {:ok, data} = Lingo.Api.Poll.get_answer_voters(channel_id, msg.id, 1)
      assert is_map(data)
    end
  end

  # -- Guild Commands --

  describe "guild command CRUD" do
    test "create, list, get, edit, and delete a guild command", %{
      guild_id: guild_id,
      app_id: app_id
    } do
      name = "lingo_guild_test_#{:rand.uniform(99999)}"

      params = %{
        "name" => name,
        "description" => "Integration test guild command",
        "type" => 1
      }

      # Create
      assert {:ok, created} = Lingo.Api.Command.create_guild(app_id, guild_id, params)
      assert created.name == name
      assert is_binary(created.id)
      command_id = created.id

      # List
      assert {:ok, commands} = Lingo.Api.Command.list_guild(app_id, guild_id)
      assert is_list(commands)
      assert Enum.any?(commands, &(&1.id == command_id))

      # Get
      assert {:ok, fetched} = Lingo.Api.Command.get_guild(app_id, guild_id, command_id)
      assert fetched.id == command_id
      assert fetched.name == name

      # Edit
      new_desc = "Updated description"

      assert {:ok, edited} =
               Lingo.Api.Command.edit_guild(app_id, guild_id, command_id, %{
                 "description" => new_desc
               })

      assert edited.id == command_id
      assert edited.description == new_desc

      # Delete
      assert :ok = Lingo.Api.Command.delete_guild(app_id, guild_id, command_id)

      Process.sleep(500)
      assert {:ok, remaining} = Lingo.Api.Command.list_guild(app_id, guild_id)
      refute Enum.any?(remaining, &(&1.id == command_id))
    end
  end

  describe "guild command bulk overwrite" do
    test "bulk_overwrite_guild replaces guild commands", %{guild_id: guild_id, app_id: app_id} do
      name1 = "lingo_gbulk_a_#{:rand.uniform(99999)}"
      name2 = "lingo_gbulk_b_#{:rand.uniform(99999)}"

      commands = [
        %{"name" => name1, "description" => "Guild bulk A", "type" => 1},
        %{"name" => name2, "description" => "Guild bulk B", "type" => 1}
      ]

      assert {:ok, result} = Lingo.Api.Command.bulk_overwrite_guild(app_id, guild_id, commands)
      assert is_list(result)
      assert length(result) >= 2

      names = Enum.map(result, & &1.name)
      assert name1 in names
      assert name2 in names

      # Clean up
      for cmd <- result, cmd.name in [name1, name2] do
        Lingo.Api.Command.delete_guild(app_id, guild_id, cmd.id)
      end
    end
  end
end
