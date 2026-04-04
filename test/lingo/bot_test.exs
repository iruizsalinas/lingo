defmodule Lingo.BotTest do
  use ExUnit.Case, async: true

  defmodule PingBot do
    use Lingo.Bot

    command "ping", "Responds with pong" do
      _ = ctx
      :pong
    end
  end

  defmodule FullBot do
    use Lingo.Bot

    command "greet", "Greets a user",
      options: [
        user("target", "The user to greet", required: true),
        string("message", "Custom greeting"),
        integer("times", "Repeat count", min_value: 1, max_value: 10),
        boolean("ephemeral", "Only visible to you"),
        channel("channel", "Channel to greet in", channel_types: [0]),
        role("role", "Role to mention"),
        number("score", "Score value", min_value: 0.0, max_value: 100.0),
        attachment("image", "An image to attach")
      ] do
      _ = ctx
      :greeted
    end

    command "admin", "Admin only",
      options: [
        string("action", "What to do",
          required: true,
          choices: [%{"name" => "Purge", "value" => "purge"}]
        )
      ] do
      _ = ctx
      :admin_action
    end

    handle :message_create, msg do
      {:message_received, msg}
    end

    handle :guild_member_add, member do
      {:member_joined, member}
    end
  end

  defmodule EmptyBot do
    use Lingo.Bot
  end

  defmodule ComponentBot do
    use Lingo.Bot

    component "confirm_delete", ctx do
      {:confirmed, ctx.custom_id}
    end

    component "role-select", ctx do
      {:selected, ctx.values}
    end
  end

  defmodule ModalBot do
    use Lingo.Bot

    modal "feedback-form", ctx do
      {:submitted, option(ctx, :name)}
    end
  end

  defmodule ContextMenuBot do
    use Lingo.Bot

    command "ping", "Pong" do
      :pong
    end

    user_command "Report User" do
      {:reported, ctx.target_id}
    end

    message_command "Bookmark" do
      {:bookmarked, ctx.target_id}
    end
  end

  defmodule FallbackBot do
    use Lingo.Bot

    handle :interaction_create, interaction do
      {:fallback, interaction}
    end
  end

  describe "command registration" do
    test "single command bot" do
      commands = PingBot.__commands__()
      assert length(commands) == 1
      assert hd(commands).name == "ping"
      assert hd(commands).description == "Responds with pong"
      assert hd(commands).options == []
    end

    test "multi-command bot with complex options" do
      commands = FullBot.__commands__()
      assert length(commands) == 2

      greet = Enum.find(commands, &(&1.name == "greet"))
      assert greet.description == "Greets a user"
      assert length(greet.options) == 8

      [target, message, times, ephemeral, channel, role_opt, score, image] = greet.options

      assert target.type == :user
      assert target.name == "target"
      assert target.required == true

      assert message.type == :string
      assert message.required == false

      assert times.type == :integer
      assert times.min_value == 1
      assert times.max_value == 10

      assert ephemeral.type == :boolean

      assert channel.type == :channel
      assert channel.channel_types == [0]

      assert role_opt.type == :role

      assert score.type == :number
      assert score.min_value == 0.0
      assert score.max_value == 100.0

      assert image.type == :attachment
    end

    test "command with choices" do
      commands = FullBot.__commands__()
      admin = Enum.find(commands, &(&1.name == "admin"))
      [action_opt] = admin.options
      assert action_opt.choices == [%{"name" => "Purge", "value" => "purge"}]
    end

    test "empty bot has no commands" do
      assert EmptyBot.__commands__() == []
    end
  end

  describe "command dispatch" do
    test "routes to correct handler" do
      assert PingBot.__handle_command__("ping", %{}) == :pong
      assert FullBot.__handle_command__("greet", %{}) == :greeted
      assert FullBot.__handle_command__("admin", %{}) == :admin_action
    end

    test "returns :unknown_command for unregistered names" do
      assert PingBot.__handle_command__("nonexistent", %{}) == :unknown_command
      assert EmptyBot.__handle_command__("anything", %{}) == :unknown_command
    end
  end

  describe "event dispatch" do
    test "routes to registered event handlers" do
      assert FullBot.__handle_event__(:message_create, "test") == {:message_received, "test"}

      assert FullBot.__handle_event__(:guild_member_add, %{name: "alice"}) ==
               {:member_joined, %{name: "alice"}}
    end

    test "unregistered events return :ok" do
      assert FullBot.__handle_event__(:guild_delete, nil) == :ok
      assert PingBot.__handle_event__(:message_create, nil) == :ok
      assert EmptyBot.__handle_event__(:anything, nil) == :ok
    end
  end

  describe "component dispatch" do
    test "routes by custom_id" do
      ctx = %Lingo.Command.Context{custom_id: "confirm_delete"}

      assert ComponentBot.__handle_component__("confirm_delete", ctx) ==
               {:confirmed, "confirm_delete"}
    end

    test "handles hyphenated custom_ids" do
      ctx = %Lingo.Command.Context{custom_id: "role-select", values: ["admin", "mod"]}

      assert ComponentBot.__handle_component__("role-select", ctx) ==
               {:selected, ["admin", "mod"]}
    end

    test "unmatched custom_ids return :ok" do
      assert ComponentBot.__handle_component__("unknown", %{}) == :ok
    end

    test "not generated when no component macros used" do
      refute function_exported?(EmptyBot, :__handle_component__, 2)
      refute function_exported?(PingBot, :__handle_component__, 2)
      refute function_exported?(FallbackBot, :__handle_component__, 2)
    end

    test "generated when component macros used" do
      assert function_exported?(ComponentBot, :__handle_component__, 2)
    end
  end

  describe "modal dispatch" do
    test "routes by custom_id" do
      ctx = %Lingo.Command.Context{options: %{name: "Alice"}}
      assert ModalBot.__handle_modal__("feedback-form", ctx) == {:submitted, "Alice"}
    end

    test "unmatched custom_ids return :ok" do
      assert ModalBot.__handle_modal__("unknown", %{}) == :ok
    end

    test "not generated when no modal macros used" do
      refute function_exported?(EmptyBot, :__handle_modal__, 2)
      refute function_exported?(ComponentBot, :__handle_modal__, 2)
    end

    test "generated when modal macros used" do
      assert function_exported?(ModalBot, :__handle_modal__, 2)
    end
  end

  describe "context menu commands" do
    test "registers user and message commands alongside slash commands" do
      commands = ContextMenuBot.__commands__()
      assert length(commands) == 3

      ping = Enum.find(commands, &(&1.name == "ping"))
      assert ping.type == :chat_input

      report = Enum.find(commands, &(&1.name == "Report User"))
      assert report.type == :user
      assert report.description == ""

      bookmark = Enum.find(commands, &(&1.name == "Bookmark"))
      assert bookmark.type == :message
      assert bookmark.description == ""
    end

    test "dispatches through __handle_command__" do
      ctx = %Lingo.Command.Context{target_id: "123456"}
      assert ContextMenuBot.__handle_command__("Report User", ctx) == {:reported, "123456"}
      assert ContextMenuBot.__handle_command__("Bookmark", ctx) == {:bookmarked, "123456"}
      assert ContextMenuBot.__handle_command__("ping", ctx) == :pong
    end
  end

  describe "fallback behavior" do
    test "bots with handle :interaction_create still work" do
      assert FallbackBot.__handle_event__(:interaction_create, :test_data) ==
               {:fallback, :test_data}
    end
  end
end
