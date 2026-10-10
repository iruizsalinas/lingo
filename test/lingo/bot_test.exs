defmodule Lingo.BotTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Lingo.Context

  defmodule PingBot do
    use Lingo.Bot

    command("ping", "Responds with pong")

    @impl true
    def handle_command("ping", _ctx), do: :pong
  end

  defmodule FullBot do
    use Lingo.Bot

    command("greet", "Greets a user",
      options: [
        user("target", "The user to greet", required: true),
        string("message", "Custom greeting"),
        integer("times", "Repeat count", min_value: 1, max_value: 10),
        boolean("ephemeral", "Only visible to you"),
        channel("channel", "Channel to greet in", channel_types: [:guild_text]),
        role("role", "Role to mention"),
        number("score", "Score value", min_value: 0.0, max_value: 100.0),
        attachment("image", "An image to attach")
      ]
    )

    command(:admin, "Admin only",
      options: [
        string(:action, "What to do",
          required: true,
          choices: [%{"name" => "Purge", "value" => "purge"}]
        ),
        string(:lingo_bot_test_unique_option, "Only declared here")
      ]
    )

    @impl true
    def handle_command("greet", _ctx), do: :greeted
    def handle_command("admin", _ctx), do: :admin_action

    @impl true
    def handle_event(:message_create, msg), do: {:message_received, msg}
    def handle_event(:guild_member_add, member), do: {:member_joined, member}
  end

  defmodule EmptyBot do
    use Lingo.Bot
  end

  defmodule ComponentBot do
    use Lingo.Bot

    @impl true
    def handle_component("confirm_delete", ctx), do: {:confirmed, ctx.custom_id}
    def handle_component("vote:" <> choice, _ctx), do: {:voted, choice}
    def handle_component("role-select", ctx), do: {:selected, ctx.values}
  end

  defmodule ModalBot do
    use Lingo.Bot

    @impl true
    def handle_modal("feedback-form", ctx), do: {:submitted, modal_value(ctx, :name)}
  end

  describe "callbacks" do
    test "are plain functions" do
      assert PingBot.handle_command("ping", %Context{}) == :pong
      assert FullBot.handle_command("greet", %Context{}) == :greeted
      assert FullBot.handle_event(:message_create, "test") == {:message_received, "test"}
    end

    test "can pattern match on custom ids" do
      assert ComponentBot.handle_component("vote:yes", %Context{}) == {:voted, "yes"}

      assert ComponentBot.handle_component("role-select", %Context{values: ["a", "b"]}) ==
               {:selected, ["a", "b"]}

      assert ModalBot.handle_modal("feedback-form", %Context{options: %{"name" => "Alice"}}) ==
               {:submitted, "Alice"}
    end

    test "unmatched input is ignored" do
      assert ComponentBot.handle_component("unknown", %Context{}) == :ok
      assert ModalBot.handle_modal("unknown", %Context{}) == :ok
      assert FullBot.handle_event(:guild_delete, nil) == :ok

      log = capture_log(fn -> assert PingBot.handle_command("gone", %Context{}) == :ok end)
      assert log =~ "no handle_command/2 clause for \"gone\""
    end

    test "only the callbacks a bot implements are defined" do
      refute function_exported?(EmptyBot, :handle_event, 2)
      refute function_exported?(PingBot, :handle_component, 2)
      refute function_exported?(ComponentBot, :handle_modal, 2)
      assert function_exported?(ComponentBot, :handle_component, 2)
    end

    test "Lingo.Bot is a behaviour" do
      behaviours = PingBot.module_info(:attributes) |> Keyword.get_values(:behaviour)
      assert Lingo.Bot in List.flatten(behaviours)
    end
  end
end
