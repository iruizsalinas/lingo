defmodule Lingo.Bot.SyncTest do
  use ExUnit.Case, async: true

  defmodule LaunchBot do
    use Lingo.Bot

    command("ping", "Pong")
    entry_point_command("launch", "Play")

    @impl true
    def handle_command(_name, _ctx), do: :ok
  end

  defmodule PingBot do
    use Lingo.Bot

    command("ping", "Pong")

    @impl true
    def handle_command(_name, _ctx), do: :ok
  end

  # Discord with an Activities app: it refuses to drop the "Launch" entry point
  defp http(test_pid) do
    fn method, url, _headers, body ->
      path = URI.parse(url).path
      body = body && body |> elem(1) |> IO.iodata_to_binary() |> JSON.decode!()
      send(test_pid, {:request, method, path, body})

      {status, response} =
        case {method, path} do
          {:get, "/api/v10/applications/app/commands"} ->
            {200, [%{"id" => "1", "name" => "Launch", "type" => 4, "handler" => 2}]}

          {:put, "/api/v10/applications/app/commands"} ->
            if Enum.any?(body, &(&1["type"] == 4)),
              do: {200, body},
              else: {400, %{"code" => 50240, "message" => "Cannot remove entry point"}}

          {:put, _guild} ->
            {200, body}
        end

      {:ok,
       %{
         status: status,
         headers: [{"content-type", "application/json"}],
         body: JSON.encode!(response)
       }}
    end
  end

  defp start(bot) do
    Lingo.TestBot.start(
      bot: bot,
      http_request: http(self()),
      application_id: "app",
      start: [:rate_limiter]
    )
  end

  test "keeps Discord's entry point when the bot declares none" do
    start(PingBot)

    assert {:ok, commands} = Lingo.register_commands()

    assert Enum.map(commands, &{&1.name, &1.type}) == [
             {"ping", :chat_input},
             {"Launch", :primary_entry_point}
           ]

    assert_receive {:request, :get, "/api/v10/applications/app/commands", nil}
  end

  test "a declared entry point is registered globally, never for guilds" do
    start(LaunchBot)

    assert {:ok, [_ping, %{name: "launch"}]} = Lingo.register_commands()
    refute_receive {:request, :get, _path, _body}

    assert {:ok, [%{name: "ping"}]} = Lingo.register_commands({:guild, "g1"})
    assert_receive {:request, :put, "/api/v10/applications/app/guilds/g1/commands", [_ping]}
  end
end
