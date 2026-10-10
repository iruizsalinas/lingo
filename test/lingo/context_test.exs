defmodule Lingo.ContextTest do
  use ExUnit.Case, async: true

  alias Lingo.Context
  alias Lingo.Type.Interaction

  describe "new/2 for commands" do
    test "builds context from guild interaction" do
      interaction =
        Interaction.new(%{
          "id" => "int1",
          "application_id" => "app1",
          "type" => 2,
          "token" => "tok123",
          "guild_id" => "g1",
          "channel_id" => "c1",
          "member" => %{
            "user" => %{"id" => "u1", "username" => "alice", "discriminator" => "0"},
            "nick" => "Ali",
            "roles" => ["r1"]
          },
          "data" => %{
            "name" => "ban",
            "options" => [
              %{"type" => 6, "name" => "user", "value" => "u2"},
              %{"type" => 3, "name" => "reason", "value" => "spam"}
            ]
          }
        })

      ctx = Context.new(interaction)

      assert ctx.interaction_id == "int1"
      assert ctx.interaction_token == "tok123"
      assert ctx.application_id == "app1"
      assert ctx.guild_id == "g1"
      assert ctx.channel_id == "c1"
      assert ctx.user_id == "u1"
      assert ctx.member.guild_id == "g1"
      assert ctx.command_name == "ban"
      assert ctx.replied == false
      assert ctx.deferred == false
    end

    test "builds context from DM interaction" do
      interaction =
        Interaction.new(%{
          "id" => "int2",
          "application_id" => "app1",
          "type" => 2,
          "token" => "tok456",
          "user" => %{"id" => "u3", "username" => "bob", "discriminator" => "0"},
          "data" => %{"name" => "ping"}
        })

      ctx = Context.new(interaction)
      assert ctx.guild_id == nil
      assert ctx.user_id == "u3"
      assert ctx.member == nil
    end
  end

  describe "new/2 for components" do
    test "builds context for button interaction" do
      interaction =
        Interaction.new(%{
          "id" => "int1",
          "application_id" => "app1",
          "type" => 3,
          "token" => "tok",
          "guild_id" => "g1",
          "channel_id" => "c1",
          "member" => %{
            "user" => %{"id" => "u1", "username" => "alice", "discriminator" => "0"},
            "roles" => []
          },
          "data" => %{
            "custom_id" => "confirm_delete",
            "component_type" => 2
          },
          "message" => %{
            "id" => "msg1",
            "channel_id" => "c1",
            "content" => "Are you sure?",
            "timestamp" => "2024-01-01T00:00:00Z"
          }
        })

      ctx = Context.new(interaction)
      assert ctx.custom_id == "confirm_delete"
      assert ctx.component_type == :button
      assert ctx.values == []
      assert ctx.message.content == "Are you sure?"
      assert ctx.message.guild_id == "g1"
      assert ctx.user_id == "u1"
      assert ctx.guild_id == "g1"
    end

    test "builds context for select menu interaction" do
      interaction =
        Interaction.new(%{
          "id" => "int2",
          "application_id" => "app1",
          "type" => 3,
          "token" => "tok",
          "data" => %{
            "custom_id" => "color_picker",
            "component_type" => 3,
            "values" => ["red", "blue"]
          },
          "user" => %{"id" => "u2", "username" => "bob", "discriminator" => "0"}
        })

      ctx = Context.new(interaction)
      assert ctx.custom_id == "color_picker"
      assert ctx.values == ["red", "blue"]
      assert ctx.component_type == :string_select
    end
  end

  describe "new/2 for modals" do
    test "parses V1 modal submission (action row wrapping)" do
      interaction =
        Interaction.new(%{
          "id" => "int1",
          "application_id" => "app1",
          "type" => 5,
          "token" => "tok",
          "user" => %{"id" => "u1", "username" => "alice", "discriminator" => "0"},
          "data" => %{
            "custom_id" => "feedback_form",
            "components" => [
              %{
                "type" => 1,
                "components" => [
                  %{"type" => 4, "custom_id" => "name", "value" => "Alice"}
                ]
              },
              %{
                "type" => 1,
                "components" => [
                  %{"type" => 4, "custom_id" => "comment", "value" => "Great bot!"}
                ]
              }
            ]
          }
        })

      ctx = Context.new(interaction)
      assert ctx.custom_id == "feedback_form"
      assert Lingo.Context.option(ctx, :name) == "Alice"
      assert Lingo.Context.option(ctx, :comment) == "Great bot!"
      assert Lingo.Context.modal_value(ctx, :name) == "Alice"
    end

    test "parses V2 modal submission (label wrapping)" do
      interaction =
        Interaction.new(%{
          "id" => "int2",
          "application_id" => "app1",
          "type" => 5,
          "token" => "tok",
          "user" => %{"id" => "u1", "username" => "alice", "discriminator" => "0"},
          "data" => %{
            "custom_id" => "settings_modal",
            "components" => [
              %{
                "type" => 18,
                "component" => %{
                  "type" => 4,
                  "custom_id" => "nickname",
                  "value" => "Ali"
                }
              },
              %{
                "type" => 18,
                "component" => %{
                  "type" => 3,
                  "custom_id" => "theme",
                  "values" => ["dark"]
                }
              }
            ]
          }
        })

      ctx = Context.new(interaction)
      assert ctx.custom_id == "settings_modal"
      assert Lingo.Context.option(ctx, :nickname) == "Ali"
      assert Lingo.Context.option(ctx, :theme) == ["dark"]
    end

    test "handles empty modal components" do
      interaction =
        Interaction.new(%{
          "id" => "1",
          "application_id" => "2",
          "type" => 5,
          "token" => "t",
          "user" => %{"id" => "u1", "username" => "a", "discriminator" => "0"},
          "data" => %{"custom_id" => "empty_modal"}
        })

      ctx = Context.new(interaction)
      assert ctx.options == %{}
    end

    test "does not create atoms for unknown modal custom IDs" do
      custom_id = "unknown_modal_id_#{System.unique_integer([:positive])}"
      assert_raise ArgumentError, fn -> String.to_existing_atom(custom_id) end

      interaction =
        Interaction.new(%{
          "id" => "1",
          "application_id" => "2",
          "type" => 5,
          "token" => "t",
          "user" => %{"id" => "u1", "username" => "a", "discriminator" => "0"},
          "data" => %{
            "custom_id" => "modal",
            "components" => [
              %{"type" => 18, "component" => %{"custom_id" => custom_id, "value" => "safe"}}
            ]
          }
        })

      ctx = Context.new(interaction)
      assert Lingo.Context.modal_value(ctx, custom_id) == "safe"
      assert_raise ArgumentError, fn -> String.to_existing_atom(custom_id) end
    end
  end
end
