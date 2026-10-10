defmodule Lingo.Bot.RunnerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Lingo.Context
  alias Lingo.Type.Interaction

  defmodule PingBot do
    use Lingo.Bot

    command("ping", "Responds with pong")

    @impl true
    def handle_command("ping", _ctx), do: :pong
  end

  # reports every callback, and which bot it ran for, to the test
  defmodule RecordingBot do
    use Lingo.Bot

    command("ping", "Pong")
    command("search", "Search", options: [string(:query, "What", autocomplete: true)])

    @impl true
    def handle_command(name, ctx), do: report({:command, name, ctx})

    @impl true
    def handle_autocomplete(name, ctx), do: report({:autocomplete, name, ctx})

    @impl true
    def handle_component("crash", _ctx), do: raise("boom")
    def handle_component(custom_id, ctx), do: report({:component, custom_id, ctx})

    @impl true
    def handle_event(event, data), do: report({:event, event, data})

    defp report(message),
      do: send(Lingo.Instance.get(:test_pid), {Lingo.Instance.current(), message})
  end

  defmodule EventOnlyBot do
    use Lingo.Bot

    @impl true
    def handle_event(event, data),
      do: send(Lingo.Instance.get(:test_pid), {:event, event, data})
  end

  defp focused_option_of(ctx), do: Lingo.Context.focused_option(ctx)

  defp interaction(type, data) do
    Interaction.new(%{
      "id" => "1",
      "application_id" => "2",
      "type" => type,
      "token" => "t",
      "user" => %{"id" => "3", "username" => "u"},
      "data" => data
    })
  end

  describe "dispatch" do
    test "commands run in their own process, for the right bot" do
      bot = Lingo.TestBot.start(bot: RecordingBot, test_pid: self())

      :ok = Lingo.Bot.Runner.interaction(interaction(2, %{"name" => "ping"}))

      assert_receive {^bot, {:command, "ping", %Context{bot: ^bot} = ctx}}
      assert ctx.type == :application_command
    end

    test "autocomplete and components" do
      bot = Lingo.TestBot.start(bot: RecordingBot, test_pid: self())

      autocomplete =
        interaction(4, %{
          "name" => "search",
          "options" => [%{"type" => 3, "name" => "query", "value" => "ab", "focused" => true}]
        })

      :ok = Lingo.Bot.Runner.interaction(autocomplete)
      assert_receive {^bot, {:autocomplete, "search", ctx}}
      assert focused_option_of(ctx) == {:query, "ab"}

      :ok =
        Lingo.Bot.Runner.interaction(
          interaction(3, %{"custom_id" => "vote:1", "component_type" => 2})
        )

      assert_receive {^bot, {:component, "vote:1", %Context{component_type: :button}}}
    end

    test "events" do
      bot = Lingo.TestBot.start(bot: RecordingBot, test_pid: self())
      :ok = Lingo.Bot.Runner.event(:message_create, :data)
      assert_receive {^bot, {:event, :message_create, :data}}
    end

    test "a crashing handler doesn't take anything down" do
      bot = Lingo.TestBot.start(bot: RecordingBot, test_pid: self())

      capture_log(fn ->
        :ok = Lingo.Bot.Runner.interaction(interaction(3, %{"custom_id" => "crash"}))
        :ok = Lingo.Bot.Runner.event(:after_crash, nil)
        assert_receive {^bot, {:event, :after_crash, nil}}
      end)
    end

    test "interactions without a callback reach handle_event/2" do
      Lingo.TestBot.start(bot: EventOnlyBot, test_pid: self())
      :ok = Lingo.Bot.Runner.interaction(interaction(3, %{"custom_id" => "x"}))
      assert_receive {:event, :interaction_create, %Interaction{type: :message_component}}
    end

    test "bots without handle_event/2 ignore events" do
      Lingo.TestBot.start(bot: PingBot)
      assert :ok = Lingo.Bot.Runner.event(:message_create, :data)
    end
  end
end
