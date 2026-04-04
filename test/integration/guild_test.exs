defmodule Lingo.Integration.GuildTest do
  @moduledoc false
  use Lingo.IntegrationCase

  setup do
    guild_id = System.get_env("GUILD_ID")
    if is_nil(guild_id) or guild_id == "", do: raise("GUILD_ID not set")
    %{guild_id: guild_id}
  end

  describe "get/1" do
    test "returns guild struct with id, name, owner_id", %{guild_id: guild_id} do
      assert {:ok, guild} = Lingo.Api.Guild.get(guild_id)
      assert guild.id == guild_id
      assert is_binary(guild.name)
      assert is_binary(guild.owner_id)
    end
  end

  describe "get/2 with_counts" do
    test "returns approximate_member_count when with_counts is true", %{guild_id: guild_id} do
      assert {:ok, guild} = Lingo.Api.Guild.get(guild_id, with_counts: true)
      assert guild.id == guild_id
      assert is_integer(guild.approximate_member_count)
      assert guild.approximate_member_count >= 1
    end
  end

  describe "get_preview/1" do
    test "returns guild preview with id and name", %{guild_id: guild_id} do
      assert {:ok, preview} = Lingo.Api.Guild.get_preview(guild_id)
      assert preview.id == guild_id
      assert is_binary(preview.name)
    end
  end

  describe "get_channels/1" do
    test "returns list of channels, each with a :type", %{guild_id: guild_id} do
      assert {:ok, channels} = Lingo.Api.Guild.get_channels(guild_id)
      assert is_list(channels)
      assert length(channels) > 0

      for channel <- channels do
        assert is_atom(channel.type)
      end
    end
  end

  describe "list_active_threads/1" do
    test "returns map with :threads key", %{guild_id: guild_id} do
      assert {:ok, result} = Lingo.Api.Guild.list_active_threads(guild_id)
      assert is_map(result)
      assert is_list(result.threads)
    end
  end

  describe "get_voice_regions/1" do
    test "returns a list", %{guild_id: guild_id} do
      assert {:ok, regions} = Lingo.Api.Guild.get_voice_regions(guild_id)
      assert is_list(regions)
    end
  end

  describe "get_invites/1" do
    test "returns a list", %{guild_id: guild_id} do
      assert {:ok, invites} = Lingo.Api.Guild.get_invites(guild_id)
      assert is_list(invites)
    end
  end

  describe "get_integrations/1" do
    test "returns a list", %{guild_id: guild_id} do
      assert {:ok, integrations} = Lingo.Api.Guild.get_integrations(guild_id)
      assert is_list(integrations)
    end
  end

  describe "get_widget_settings/1" do
    test "returns a map", %{guild_id: guild_id} do
      assert {:ok, settings} = Lingo.Api.Guild.get_widget_settings(guild_id)
      assert is_map(settings)
    end
  end

  describe "get_prune_count/2" do
    test "returns map with pruned key", %{guild_id: guild_id} do
      assert {:ok, result} = Lingo.Api.Guild.get_prune_count(guild_id, days: 30)
      assert is_map(result)
      assert is_integer(result["pruned"])
    end
  end

  describe "get_welcome_screen/1" do
    test "returns ok or 404 error", %{guild_id: guild_id} do
      case Lingo.Api.Guild.get_welcome_screen(guild_id) do
        {:ok, screen} -> assert is_map(screen)
        {:error, {status, _}} -> assert status in [404, 403]
      end
    end
  end

  describe "get_onboarding/1" do
    test "returns ok or error", %{guild_id: guild_id} do
      case Lingo.Api.Guild.get_onboarding(guild_id) do
        {:ok, data} -> assert is_map(data)
        {:error, {status, _}} -> assert is_integer(status)
      end
    end
  end
end
