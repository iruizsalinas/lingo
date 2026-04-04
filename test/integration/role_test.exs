defmodule Lingo.Integration.RoleTest do
  @moduledoc false
  use Lingo.IntegrationCase

  setup do
    guild_id = System.get_env("GUILD_ID")
    if is_nil(guild_id) or guild_id == "", do: raise("GUILD_ID not set")

    {:ok, role} =
      Lingo.Api.Role.create(guild_id, %{name: "lingo-test-role-#{:rand.uniform(99999)}"})

    on_exit(fn -> Lingo.Api.Role.delete(guild_id, role.id) end)

    %{guild_id: guild_id, role: role}
  end

  describe "list/1" do
    test "returns a list containing at least the @everyone role", %{guild_id: guild_id} do
      assert {:ok, roles} = Lingo.Api.Role.list(guild_id)
      assert is_list(roles)
      assert Enum.any?(roles, &(&1.name == "@everyone"))
    end
  end

  describe "create/2" do
    test "creates a role and returns it", %{role: role} do
      assert is_binary(role.id)
      assert role.name =~ "lingo-test-role-"
    end
  end

  describe "get/2" do
    test "retrieves the created role by ID", %{guild_id: guild_id, role: role} do
      assert {:ok, fetched} = Lingo.Api.Role.get(guild_id, role.id)
      assert fetched.id == role.id
      assert fetched.name == role.name
    end
  end

  describe "modify/3" do
    test "renames the role", %{guild_id: guild_id, role: role} do
      assert {:ok, updated} = Lingo.Api.Role.modify(guild_id, role.id, %{name: "renamed"})
      assert updated.id == role.id
      assert updated.name == "renamed"
    end
  end

  describe "modify_positions/2" do
    test "reorders roles", %{guild_id: guild_id, role: role} do
      assert {:ok, roles} =
               Lingo.Api.Role.modify_positions(guild_id, [%{id: role.id, position: 1}])

      assert is_list(roles)
      moved = Enum.find(roles, &(&1.id == role.id))
      assert moved != nil
    end
  end

  describe "get_member_counts/1" do
    test "returns a map of role ID to member count", %{guild_id: guild_id} do
      assert {:ok, counts} = Lingo.Api.Role.get_member_counts(guild_id)
      assert is_map(counts)
    end
  end

  describe "delete/2" do
    test "deletes a role", %{guild_id: guild_id} do
      {:ok, disposable} =
        Lingo.Api.Role.create(guild_id, %{name: "lingo-delete-me-#{:rand.uniform(99999)}"})

      assert :ok = Lingo.Api.Role.delete(guild_id, disposable.id)

      assert {:error, {404, _}} = Lingo.Api.Role.get(guild_id, disposable.id)
    end
  end
end
