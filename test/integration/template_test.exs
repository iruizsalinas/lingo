defmodule Lingo.Integration.TemplateTest do
  @moduledoc false
  use Lingo.IntegrationCase

  setup do
    guild_id = System.get_env("GUILD_ID")
    if is_nil(guild_id) or guild_id == "", do: raise("GUILD_ID not set")
    %{guild_id: guild_id}
  end

  describe "list/1" do
    test "returns {:ok, list}", %{guild_id: guild_id} do
      case Lingo.Api.Template.list(guild_id) do
        {:ok, templates} ->
          assert is_list(templates)

        {:error, {403, _}} ->
          IO.puts("skipping: guild lacks COMMUNITY feature")
      end
    end
  end

  describe "template CRUD lifecycle" do
    test "create, get, modify, sync, and delete", %{guild_id: guild_id} do
      name = "lingo-test-template"

      case Lingo.Api.Template.create(guild_id, %{name: name, description: "test"}) do
        {:ok, template} ->
          on_exit(fn ->
            Lingo.Api.Template.delete(guild_id, template.code)
          end)

          assert is_binary(template.code)
          assert template.name == name
          assert template.description == "test"
          assert template.source_guild_id == guild_id

          code = template.code

          # get by code
          assert {:ok, fetched} = Lingo.Api.Template.get(code)
          assert fetched.code == code
          assert fetched.name == name

          # modify
          assert {:ok, modified} =
                   Lingo.Api.Template.modify(guild_id, code, %{name: "renamed-template"})

          assert modified.code == code
          assert modified.name == "renamed-template"

          # sync
          assert {:ok, synced} = Lingo.Api.Template.sync(guild_id, code)
          assert synced.code == code

          # delete
          assert {:ok, _deleted} = Lingo.Api.Template.delete(guild_id, code)

          # verify deletion
          assert {:error, _} = Lingo.Api.Template.get(code)

        {:error, {403, _}} ->
          IO.puts("skipping: guild lacks COMMUNITY feature")
      end
    end
  end
end
