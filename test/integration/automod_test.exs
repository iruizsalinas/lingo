defmodule Lingo.Integration.AutomodTest do
  @moduledoc false
  use Lingo.IntegrationCase

  alias Lingo.Api.AutoModeration

  setup do
    guild_id = System.get_env("GUILD_ID")
    if is_nil(guild_id) or guild_id == "", do: raise("GUILD_ID not set")

    %{guild_id: guild_id}
  end

  defp rule_params do
    %{
      name: "lingo_test_rule_#{:rand.uniform(99999)}",
      event_type: 1,
      trigger_type: 1,
      trigger_metadata: %{keyword_filter: ["lingo_test_blocked"]},
      actions: [%{type: 1}]
    }
  end

  describe "list/1" do
    test "returns a list", %{guild_id: guild_id} do
      assert {:ok, rules} = AutoModeration.list(guild_id)
      assert is_list(rules)
    end
  end

  describe "create/2" do
    test "creates a keyword filter rule", %{guild_id: guild_id} do
      params = rule_params()
      assert {:ok, rule} = AutoModeration.create(guild_id, params)

      on_exit(fn -> AutoModeration.delete(guild_id, rule.id) end)

      assert is_binary(rule.id)
      assert rule.name == params.name
      assert rule.trigger_type == :keyword
      assert rule.event_type == :message_send
    end
  end

  describe "get/2" do
    test "retrieves the created rule by ID", %{guild_id: guild_id} do
      {:ok, rule} = AutoModeration.create(guild_id, rule_params())

      on_exit(fn -> AutoModeration.delete(guild_id, rule.id) end)

      assert {:ok, fetched} = AutoModeration.get(guild_id, rule.id)
      assert fetched.id == rule.id
      assert fetched.name == rule.name
    end
  end

  describe "update/3" do
    test "renames the rule", %{guild_id: guild_id} do
      {:ok, rule} = AutoModeration.create(guild_id, rule_params())

      on_exit(fn -> AutoModeration.delete(guild_id, rule.id) end)

      assert {:ok, updated} = AutoModeration.update(guild_id, rule.id, %{name: "renamed"})
      assert updated.id == rule.id
      assert updated.name == "renamed"
    end
  end

  describe "delete/2" do
    test "deletes the rule", %{guild_id: guild_id} do
      {:ok, rule} = AutoModeration.create(guild_id, rule_params())

      assert :ok = AutoModeration.delete(guild_id, rule.id)

      assert {:error, %Lingo.Error{status: 404}} = AutoModeration.get(guild_id, rule.id)
    end
  end
end
