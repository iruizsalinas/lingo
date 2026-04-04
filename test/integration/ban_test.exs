defmodule Lingo.Integration.BanTest do
  @moduledoc false
  use Lingo.IntegrationCase

  setup do
    guild_id = System.get_env("GUILD_ID")
    if is_nil(guild_id) or guild_id == "", do: raise("GUILD_ID not set")
    %{guild_id: guild_id}
  end

  describe "list/1" do
    test "returns {:ok, list}", %{guild_id: guild_id} do
      assert {:ok, bans} = Lingo.Api.Ban.list(guild_id)
      assert is_list(bans)
    end
  end

  describe "get/2" do
    test "returns {:error, {404, _}} for a non-existent user", %{guild_id: guild_id} do
      assert {:error, {404, _}} = Lingo.Api.Ban.get(guild_id, "1")
    end
  end

  describe "create/3" do
    test "returns error for an invalid user ID", %{guild_id: guild_id} do
      assert {:error, _} = Lingo.Api.Ban.create(guild_id, "1")
    end
  end

  describe "bulk_create/3" do
    test "returns error for invalid user IDs", %{guild_id: guild_id} do
      assert {:error, _} = Lingo.Api.Ban.bulk_create(guild_id, ["1", "2"])
    end
  end
end
