defmodule Lingo.TestingTest do
  use ExUnit.Case, async: true

  import Lingo.Testing

  defmodule SampleBot do
    use Lingo.Bot

    command("ping", "Pong")
    command("echo", "Echo", options: [string(:text, "What", required: true)])

    command("todo", "Todos",
      options: [subcommand(:add, "Add one", options: [string(:item, "What")])]
    )

    command("search", "Search", options: [string(:query, "What", autocomplete: true)])
    command("mod", "Moderators", checks: [{:permissions, [:kick_members]}])
    user_command("Wave")

    @impl true
    def handle_command("ping", ctx), do: reply!(ctx, "Pong!")
    def handle_command("echo", ctx), do: reply!(ctx, option(ctx, :text))
    def handle_command("todo", ctx), do: reply!(ctx, "added #{ctx.options.add.item}")
    def handle_command("mod", ctx), do: reply!(ctx, "ok")
    def handle_command("Wave", ctx), do: ephemeral!(ctx, "waved at #{ctx.target_id}")

    @impl true
    def handle_autocomplete("search", ctx) do
      {_name, typed} = focused_option(ctx)
      autocomplete_result!(ctx, [%{name: typed <> "!", value: typed}])
    end

    @impl true
    def handle_component("pick", ctx), do: update!(ctx, "picked #{Enum.join(ctx.values, ",")}")

    @impl true
    def handle_modal("form", ctx), do: reply!(ctx, "hello #{modal_value(ctx, "name")}")

    @impl true
    def handle_event(:message_create, message),
      do: Lingo.Api.Message.create(message.channel_id, "saw #{message.content}")

    def handle_event(_event, _data), do: :ok
  end

  setup do
    start_bot(SampleBot)
    :ok
  end

  test "commands, with options and subcommands" do
    run_command("ping")
    assert %{type: :channel_message, data: %{"content" => "Pong!"}} = await_response()

    run_command("echo", options: [text: "hi"], guild_id: nil)
    assert %{data: %{"content" => "hi"}} = await_response()

    run_command("todo", options: [add: [item: "milk"]])
    assert %{data: %{"content" => "added milk"}} = await_response()
  end

  test "context menu commands" do
    run_command("Wave", type: :user, target_id: "77")
    assert %{data: %{"content" => "waved at 77", "flags" => 64}} = await_response()
  end

  test "autocomplete, components and modals" do
    run_autocomplete("search", options: [query: "eli"], focused: :query)
    assert %{type: :autocomplete, data: %{"choices" => [%{"name" => "eli!"}]}} = await_response()

    run_component("pick", values: ["a", "b"])
    assert %{type: :update_message, data: %{"content" => "picked a,b"}} = await_response()

    submit_modal("form", %{"name" => "Ada"})
    assert %{data: %{"content" => "hello Ada"}} = await_response()
  end

  test "checks run as in production" do
    run_command("mod")
    assert %{data: %{"content" => content, "flags" => 64}} = await_response()
    assert content =~ "kick members"

    run_command("mod", permissions: Lingo.Permissions.from_list([:kick_members]))
    assert %{data: %{"content" => "ok"}} = await_response()
  end

  test "gateway dispatches update the cache and reach the bot, whose API calls are recorded" do
    dispatch("MESSAGE_CREATE", %{
      id: "5",
      channel_id: "6",
      content: "hello",
      author: %{id: "7", username: "u"}
    })

    assert %{method: :post, path: "/channels/6/messages", body: %{"content" => "saw hello"}} =
             await_request()
  end

  test "unknown commands and options are reported" do
    assert_raise ArgumentError, ~r/no chat_input command "nope"/, fn -> run_command("nope") end

    assert_raise ArgumentError, ~r/no option :size/, fn ->
      run_command("echo", options: [size: 1])
    end
  end

  test "a bot that doesn't answer fails the wait" do
    assert_raise ExUnit.AssertionError, fn -> await_response(50) end
  end
end
