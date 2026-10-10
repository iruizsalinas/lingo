defmodule Lingo.Bot.CommandsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

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

  defmodule ContextMenuBot do
    use Lingo.Bot

    command("ping", "Pong")
    user_command("Report User")
    message_command("Bookmark", nsfw: true)

    @impl true
    def handle_command("ping", _ctx), do: :pong
    def handle_command("Report User", ctx), do: {:reported, ctx.target_id}
    def handle_command("Bookmark", ctx), do: {:bookmarked, ctx.target_id}
  end

  describe "command declarations" do
    test "single command bot" do
      assert [command] = PingBot.__commands__()
      assert command.name == "ping"
      assert command.description == "Responds with pong"
      assert command.options == []
    end

    test "options, in order" do
      greet = Enum.find(FullBot.__commands__(), &(&1.name == "greet"))
      assert greet.description == "Greets a user"

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
      assert channel.channel_types == [:guild_text]
      assert role_opt.type == :role
      assert score.type == :number
      assert score.min_value == 0.0
      assert image.type == :attachment
    end

    test "atom names become strings" do
      admin = Enum.find(FullBot.__commands__(), &(&1.name == "admin"))
      assert [action, _unique] = admin.options
      assert action.name == "action"
      assert action.choices == [%{"name" => "Purge", "value" => "purge"}]
    end

    test "channel types are sent to Discord as numbers" do
      greet = Enum.find(FullBot.__commands__(), &(&1.name == "greet"))
      payload = Lingo.Type.ApplicationCommand.to_payload(greet)
      channel = Enum.find(payload["options"], &(&1["name"] == "channel"))
      assert channel["channel_types"] == [0]
    end

    test "declared option names exist as atoms" do
      assert :lingo_bot_test_unique_option in FullBot.__option_names__()
      assert String.to_existing_atom("lingo_bot_test_unique_option")
    end

    test "context menu commands" do
      commands = ContextMenuBot.__commands__()

      assert Enum.map(commands, &{&1.name, &1.type}) ==
               [{"ping", :chat_input}, {"Report User", :user}, {"Bookmark", :message}]

      bookmark = Enum.find(commands, &(&1.name == "Bookmark"))
      assert bookmark.description == ""
      assert bookmark.nsfw == true
    end

    test "empty bot" do
      assert EmptyBot.__commands__() == []
    end

    test "a do block points at handle_command/2" do
      error =
        assert_raise CompileError, fn ->
          Code.compile_string("""
          defmodule Lingo.BotTest.OldStyle do
            use Lingo.Bot
            command "ping", "Pong" do
              :pong
            end
          end
          """)
        end

      assert Exception.message(error) =~ "handle_command/2"
    end

    test "duplicate commands don't compile" do
      assert_raise CompileError, ~r/twice/, fn ->
        Code.compile_string("""
        defmodule Lingo.BotTest.Duplicate do
          use Lingo.Bot
          command "ping", "Pong"
          command "ping", "Pong again"
          def handle_command(_name, _ctx), do: :ok
        end
        """)
      end
    end

    test "unknown command options don't compile" do
      assert_raise ArgumentError, ~r/unknown command options/, fn ->
        Code.compile_string("""
        defmodule Lingo.BotTest.BadOption do
          use Lingo.Bot
          command "ping", "Pong", descripton: "typo"
          def handle_command(_name, _ctx), do: :ok
        end
        """)
      end
    end

    test "warns about commands without handle_command/2" do
      warning =
        capture_io(:stderr, fn ->
          Code.compile_string("""
          defmodule Lingo.BotTest.Unhandled do
            use Lingo.Bot
            command "ping", "Pong"
          end
          """)
        end)

      assert warning =~ "doesn't define handle_command/2"
    end

    test "warns about autocomplete options without handle_autocomplete/2" do
      warning =
        capture_io(:stderr, fn ->
          Code.compile_string("""
          defmodule Lingo.BotTest.NoAutocomplete do
            use Lingo.Bot
            command "search", "Search", options: [string(:query, "What", autocomplete: true)]
            def handle_command(_name, _ctx), do: :ok
          end
          """)
        end)

      assert warning =~ "doesn't define handle_autocomplete/2"
    end
  end
end
