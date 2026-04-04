defmodule Lingo.Command.ContextTest do
  use ExUnit.Case, async: true

  alias Lingo.Command.Context
  alias Lingo.Type.Interaction

  describe "from_interaction/1" do
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

      ctx = Context.from_interaction(interaction)

      assert ctx.interaction_id == "int1"
      assert ctx.interaction_token == "tok123"
      assert ctx.application_id == "app1"
      assert ctx.guild_id == "g1"
      assert ctx.channel_id == "c1"
      assert ctx.user_id == "u1"
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

      ctx = Context.from_interaction(interaction)
      assert ctx.guild_id == nil
      assert ctx.user_id == "u3"
      assert ctx.member == nil
    end
  end

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

      ctx = Context.from_interaction(interaction)

      assert Context.option(ctx, "color") == "blue"
      assert Context.option(ctx, "count") == 5
      assert Context.option(ctx, "verbose") == true
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

      ctx = Context.from_interaction(interaction)
      assert Context.option(ctx, "nonexistent") == nil
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

      ctx = Context.from_interaction(interaction)
      assert Context.option(ctx, "anything") == nil
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

      ctx = Context.from_interaction(interaction)
      assert Context.option(ctx, "target") == "user_snowflake"
      assert Context.option(ctx, "days") == 7
      assert Context.option(ctx, "silent") == false
    end
  end

  describe "from_interaction/1 with target_id" do
    test "captures target_id for context menu commands" do
      interaction =
        Interaction.new(%{
          "id" => "1",
          "application_id" => "2",
          "type" => 2,
          "token" => "t",
          "member" => %{
            "user" => %{"id" => "u1", "username" => "alice", "discriminator" => "0"},
            "roles" => []
          },
          "guild_id" => "g1",
          "data" => %{
            "name" => "Report User",
            "type" => 2,
            "target_id" => "target_user_123",
            "resolved" => %{
              "users" => %{
                "target_user_123" => %{
                  "id" => "target_user_123",
                  "username" => "badguy",
                  "discriminator" => "0"
                }
              }
            }
          }
        })

      ctx = Context.from_interaction(interaction)
      assert ctx.target_id == "target_user_123"
      assert ctx.command_name == "Report User"

      user = Context.resolved_user(ctx, "target_user_123")
      assert user.username == "badguy"
    end
  end

  describe "from_component/1" do
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

      ctx = Context.from_component(interaction)
      assert ctx.custom_id == "confirm_delete"
      assert ctx.component_type == 2
      assert ctx.values == []
      assert ctx.message.content == "Are you sure?"
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

      ctx = Context.from_component(interaction)
      assert ctx.custom_id == "color_picker"
      assert ctx.values == ["red", "blue"]
      assert ctx.component_type == 3
    end
  end

  describe "from_modal/1" do
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

      ctx = Context.from_modal(interaction)
      assert ctx.custom_id == "feedback_form"
      assert Context.option(ctx, :name) == "Alice"
      assert Context.option(ctx, :comment) == "Great bot!"
      assert Context.modal_value(ctx, :name) == "Alice"
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

      ctx = Context.from_modal(interaction)
      assert ctx.custom_id == "settings_modal"
      assert Context.option(ctx, :nickname) == "Ali"
      assert Context.option(ctx, :theme) == ["dark"]
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

      ctx = Context.from_modal(interaction)
      assert ctx.options == %{}
    end
  end

  describe "modal_value/2" do
    test "is an alias for option/2" do
      ctx = %Context{options: %{name: "Alice", age: "25"}}
      assert Context.modal_value(ctx, :name) == Context.option(ctx, :name)
      assert Context.modal_value(ctx, "age") == Context.option(ctx, "age")
    end
  end
end
