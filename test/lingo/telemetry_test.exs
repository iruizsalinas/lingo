defmodule Lingo.TelemetryTest do
  use ExUnit.Case, async: true

  alias Lingo.Telemetry

  defmodule SpanBot do
    use Lingo.Bot

    command("ping", "Pong")
    command("guarded", "Guild only", checks: [:guild_only])

    @impl true
    def handle_command("ping", _ctx), do: :pong
    def handle_command("guarded", _ctx), do: :ran

    @impl true
    def handle_event(:boom, _data), do: raise("boom")
    def handle_event(_event, _data), do: :ok

    @impl true
    def handle_error(_error, _source), do: :ok
  end

  @events [
    [:lingo, :rest, :request, :start],
    [:lingo, :rest, :request, :stop],
    [:lingo, :command, :start],
    [:lingo, :command, :stop],
    [:lingo, :command, :check_failed],
    [:lingo, :event, :start],
    [:lingo, :event, :stop],
    [:lingo, :event, :exception],
    [:lingo, :event, :parse_failed]
  ]

  # handlers are global, so each test only hears its own bot
  setup do
    test_pid = self()

    http = fn _method, _url, _headers, _body ->
      {:ok, %{status: 204, headers: [], body: ""}}
    end

    bot = Lingo.TestBot.start(bot: SpanBot, http_request: http, start: [:rate_limiter])
    id = {__MODULE__, bot}

    :telemetry.attach_many(id, @events, &__MODULE__.handle/4, %{bot: bot, pid: test_pid})

    on_exit(fn -> :telemetry.detach(id) end)
    %{bot: bot}
  end

  def handle(event, measurements, metadata, %{bot: bot, pid: pid}) do
    if metadata[:bot] == bot, do: send(pid, {:telemetry, event, measurements, metadata})
  end

  defp command(name, opts \\ []) do
    payload = %{
      "id" => "1",
      "application_id" => "2",
      "type" => 2,
      "token" => "t",
      "channel_id" => "50",
      "user" => %{"id" => "4", "username" => "u"},
      "data" => %{"id" => "3", "name" => name, "type" => 1}
    }

    payload = if opts[:guild], do: Map.put(payload, "guild_id", "60"), else: payload
    Lingo.Type.Interaction.new(payload)
  end

  test "API requests are spans" do
    assert :ok = Lingo.Api.Message.delete("1", "2")

    assert_receive {:telemetry, [:lingo, :rest, :request, :start], %{system_time: _},
                    %{method: :delete, path: "/channels/1/messages/2"}}

    assert_receive {:telemetry, [:lingo, :rest, :request, :stop], %{duration: duration},
                    %{method: :delete, status: 204}}

    assert duration >= 0
  end

  test "commands are spans, with their checks" do
    Lingo.Bot.Runner.interaction(command("ping", guild: true))

    assert_receive {:telemetry, [:lingo, :command, :start], _,
                    %{command_name: "ping", type: :chat_input, guild_id: "60", user_id: "4"}}

    assert_receive {:telemetry, [:lingo, :command, :stop], %{duration: _},
                    %{command_name: "ping"}}

    Lingo.Bot.Runner.interaction(command("guarded"))

    assert_receive {:telemetry, [:lingo, :command, :check_failed], _,
                    %{command_name: "guarded", reason: :guild_only}}
  end

  @tag :capture_log
  test "a handler that raises ends its span with :exception" do
    Lingo.Bot.Runner.event(:boom, nil)
    assert_receive {:telemetry, [:lingo, :event, :start], _, %{event: :boom}}

    assert_receive {:telemetry, [:lingo, :event, :exception], %{duration: _},
                    %{event: :boom, kind: :error, reason: %RuntimeError{}}}
  end

  @tag :capture_log
  test "events Lingo can't parse are reported" do
    Lingo.Gateway.Dispatcher.dispatch(:guild_role_create, %{"role" => "not a role"})
    assert_receive {:telemetry, [:lingo, :event, :parse_failed], _, %{event: :guild_role_create}}
  end

  test "span/3 raises again what its function raised" do
    assert_raise RuntimeError, "inner", fn ->
      Telemetry.span([:test], %{}, fn -> raise "inner" end)
    end

    assert Telemetry.span([:test], %{}, fn -> {:value, %{}} end) == :value
  end
end
