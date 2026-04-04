defmodule Lingo.Integration.CommandLifecycleTest do
  @moduledoc false
  use Lingo.IntegrationCase

  @test_command_name "lingo_test_cmd_#{:rand.uniform(99999)}"

  describe "global command CRUD" do
    test "create, list, and delete a global command", ctx do
      app_id = ctx.client_id

      params = %{
        "name" => @test_command_name,
        "description" => "Lingo integration test command",
        "type" => 1,
        "options" => [
          %{
            "type" => 3,
            "name" => "input",
            "description" => "Test input",
            "required" => false
          }
        ]
      }

      assert {:ok, created} = Lingo.Api.Command.create_global(app_id, params)
      assert created.name == @test_command_name
      assert created.description == "Lingo integration test command"
      assert is_binary(created.id)
      assert length(created.options) == 1
      assert hd(created.options).type == :string

      command_id = created.id

      assert {:ok, commands} = Lingo.Api.Command.list_global(app_id)
      assert is_list(commands)

      found = Enum.find(commands, &(&1.id == command_id))
      assert found != nil, "Created command not found in list"
      assert found.name == @test_command_name

      assert :ok = Lingo.Api.Command.delete_global(app_id, command_id)

      Process.sleep(500)
      assert {:ok, commands_after} = Lingo.Api.Command.list_global(app_id)
      refute Enum.any?(commands_after, &(&1.id == command_id))
    end
  end

  describe "command serialization roundtrip" do
    test "Lingo.Type.ApplicationCommand serializes and Discord accepts it", ctx do
      app_id = ctx.client_id
      name = "lingo_serial_test_#{:rand.uniform(99999)}"

      cmd = %Lingo.Type.ApplicationCommand{
        name: name,
        description: "Serialization roundtrip test",
        options: [
          %Lingo.Type.CommandOption{
            type: :integer,
            name: "count",
            description: "How many",
            required: true,
            min_value: 1,
            max_value: 100
          },
          %Lingo.Type.CommandOption{
            type: :boolean,
            name: "verbose",
            description: "Show details"
          }
        ]
      }

      payload = Lingo.Type.ApplicationCommand.to_payload(cmd)

      assert {:ok, created} = Lingo.Api.Command.create_global(app_id, payload)
      assert created.name == name
      assert length(created.options) == 2

      [count_opt, verbose_opt] = created.options
      assert count_opt.type == :integer
      assert count_opt.required == true
      assert verbose_opt.type == :boolean
      assert verbose_opt.required == false

      :ok = Lingo.Api.Command.delete_global(app_id, created.id)
    end
  end

  describe "bulk overwrite" do
    test "replaces all commands atomically", ctx do
      app_id = ctx.client_id
      name1 = "lingo_bulk_a_#{:rand.uniform(99999)}"
      name2 = "lingo_bulk_b_#{:rand.uniform(99999)}"

      commands = [
        %{"name" => name1, "description" => "Bulk test A", "type" => 1},
        %{"name" => name2, "description" => "Bulk test B", "type" => 1}
      ]

      assert {:ok, result} = Lingo.Api.Command.bulk_overwrite_global(app_id, commands)
      assert length(result) >= 2

      names = Enum.map(result, & &1.name)
      assert name1 in names
      assert name2 in names

      # clean up
      for cmd <- result, cmd.name in [name1, name2] do
        Lingo.Api.Command.delete_global(app_id, cmd.id)
      end
    end
  end
end
