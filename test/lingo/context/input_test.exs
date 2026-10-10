defmodule Lingo.Context.InputTest do
  use ExUnit.Case, async: true

  alias Lingo.Context
  alias Lingo.Type.Interaction

  describe "option/2" do
    test "retrieves option value by name" do
      interaction =
        Interaction.new(%{
          "id" => "1",
          "application_id" => "2",
          "type" => 2,
          "token" => "t",
          "data" => %{
            "name" => "cmd",
            "options" => [
              %{"type" => 3, "name" => "color", "value" => "blue"},
              %{"type" => 4, "name" => "count", "value" => 5},
              %{"type" => 5, "name" => "verbose", "value" => true}
            ]
          }
        })

      ctx = Context.new(interaction)

      assert Lingo.Context.option(ctx, "color") == "blue"
      assert Lingo.Context.option(ctx, "count") == 5
      assert Lingo.Context.option(ctx, "verbose") == true
    end

    test "returns nil for missing option" do
      interaction =
        Interaction.new(%{
          "id" => "1",
          "application_id" => "2",
          "type" => 2,
          "token" => "t",
          "data" => %{"name" => "cmd", "options" => []}
        })

      ctx = Context.new(interaction)
      assert Lingo.Context.option(ctx, "nonexistent") == nil
    end

    test "handles nil options" do
      interaction =
        Interaction.new(%{
          "id" => "1",
          "application_id" => "2",
          "type" => 2,
          "token" => "t",
          "data" => %{"name" => "cmd"}
        })

      ctx = Context.new(interaction)
      assert Lingo.Context.option(ctx, "anything") == nil
    end

    test "does not create atoms for unknown option names" do
      option_name = "unknown_option_#{System.unique_integer([:positive])}"
      assert_raise ArgumentError, fn -> String.to_existing_atom(option_name) end

      interaction =
        Interaction.new(%{
          "id" => "1",
          "application_id" => "2",
          "type" => 2,
          "token" => "t",
          "data" => %{
            "name" => "cmd",
            "options" => [%{"type" => 3, "name" => option_name, "value" => "safe"}]
          }
        })

      ctx = Context.new(interaction)
      assert Lingo.Context.option(ctx, option_name) == "safe"
      assert_raise ArgumentError, fn -> String.to_existing_atom(option_name) end
    end
  end

  describe "option parsing edge cases" do
    test "parses multiple option types in one command" do
      interaction =
        Interaction.new(%{
          "id" => "1",
          "application_id" => "2",
          "type" => 2,
          "token" => "t",
          "data" => %{
            "name" => "cmd",
            "options" => [
              %{"type" => 6, "name" => "target", "value" => "user_snowflake"},
              %{"type" => 4, "name" => "days", "value" => 7},
              %{"type" => 5, "name" => "silent", "value" => false}
            ]
          }
        })

      ctx = Context.new(interaction)
      assert Lingo.Context.option(ctx, "target") == "user_snowflake"
      assert Lingo.Context.option(ctx, "days") == 7
      assert Lingo.Context.option(ctx, "silent") == false
    end
  end

  describe "modal_value/2" do
    test "is an alias for option/2" do
      ctx = %Context{options: %{name: "Alice", age: "25"}}
      assert Lingo.Context.modal_value(ctx, :name) == Lingo.Context.option(ctx, :name)
      assert Lingo.Context.modal_value(ctx, "age") == Lingo.Context.option(ctx, "age")
    end
  end
end
