defmodule Lingo.LifecycleTest do
  # starts whole bots, and Lingo.bots/0 is shared by the VM
  use ExUnit.Case, async: false

  alias Lingo.Type.Guild

  defmodule AlphaBot do
    use Lingo.Bot

    command("ping", "Pong", options: [string(:echo, "Something to echo")])

    @impl true
    def handle_command(_name, _ctx), do: :ok
  end

  defmodule BetaBot do
    use Lingo.Bot
  end

  # stands in for Discord: the gateway is unavailable, everything else answers
  defp http(test_pid) do
    fn method, url, headers, body ->
      path = URI.parse(url).path
      {_, auth} = List.keyfind(headers, "authorization", 0)
      send(test_pid, {:request, method, path, auth, body})

      {status, response} =
        case {method, path} do
          {:get, "/api/v10/gateway/bot"} ->
            {401, %{"message" => "401: Unauthorized", "code" => 0}}

          {:get, "/api/v10/applications/@me"} ->
            {200, %{"id" => "app1"}}

          {:put, _commands} ->
            {200, body |> elem(1) |> IO.iodata_to_binary() |> JSON.decode!()}

          {:get, "/api/v10/users/" <> id} ->
            {200, %{"id" => id, "username" => "u"}}
        end

      {:ok,
       %{
         status: status,
         headers: [{"content-type", "application/json"}],
         body: JSON.encode!(response)
       }}
    end
  end

  defp start_bot(bot, token, opts \\ []) do
    opts = [name: bot, bot: bot, token: token, http_request: http(self())] ++ opts

    start_supervised!(%{
      id: bot,
      start: {Lingo.Supervisor, :start_link, [opts]},
      type: :supervisor
    })
  end

  setup do
    Process.delete({Lingo, :current_bot})
    :ok
  end

  describe "starting" do
    test "requires a bot and a token" do
      assert_raise ArgumentError, ~r/:token/, fn -> Lingo.child_spec(bot: AlphaBot) end
      assert_raise ArgumentError, ~r/:bot/, fn -> Lingo.child_spec(token: "t") end
    end

    test "rejects unknown and invalid options" do
      assert_raise ArgumentError, fn ->
        Lingo.child_spec(bot: AlphaBot, token: "t", intent: [])
      end

      assert_raise ArgumentError, ~r/register_commands/, fn ->
        Lingo.child_spec(bot: AlphaBot, token: "t", register_commands: :everywhere)
      end

      assert_raise ArgumentError, ~r/max_wait/, fn ->
        Lingo.child_spec(bot: AlphaBot, token: "t", rate_limit: [max_wait: -1])
      end

      assert_raise ArgumentError, ~r/:count/, fn ->
        Lingo.child_spec(bot: AlphaBot, token: "t", sharding: [ids: [0]])
      end
    end

    test "child specs are per bot, so several fit in one supervisor" do
      assert Lingo.child_spec(bot: AlphaBot, token: "t").id == {Lingo, AlphaBot}
      assert Lingo.child_spec(bot: AlphaBot, token: "t", name: :alpha2).id == {Lingo, :alpha2}
    end

    test "a restarted Instance restarts the processes that read its config" do
      start_bot(AlphaBot, "token-a", cache: [guilds: true])
      instance = Process.whereis(Lingo.Instance.process_name(AlphaBot, Lingo.Instance))
      tables = Process.whereis(Lingo.Instance.process_name(AlphaBot, Lingo.Cache.Tables))

      Process.exit(instance, :kill)

      wait_until(fn ->
        Process.whereis(Lingo.Instance.process_name(AlphaBot, Lingo.Cache.Tables)) not in [
          nil,
          tables
        ]
      end)

      Lingo.put_bot(AlphaBot)
      Lingo.Cache.Store.put_guild(%Guild{id: "1", name: "A"})
      assert [%Guild{name: "A"}] = Lingo.Cache.list_guilds()
      assert {:ok, _user} = Lingo.Api.User.get("1")
    end
  end

  defp wait_until(fun, tries \\ 100) do
    cond do
      fun.() ->
        :ok

      tries == 0 ->
        flunk("timed out")

      true ->
        Process.sleep(10)
        wait_until(fun, tries - 1)
    end
  end

  describe "several bots" do
    test "each has its own config and cache" do
      start_bot(AlphaBot, "token-a", cache: [guilds: true])
      start_bot(BetaBot, "token-b", cache: [guilds: true])

      assert Enum.sort(Lingo.bots()) == [AlphaBot, BetaBot]

      Lingo.with_bot(AlphaBot, fn -> Lingo.Cache.Store.put_guild(%Guild{id: "1", name: "A"}) end)
      assert [%Guild{name: "A"}] = Lingo.with_bot(AlphaBot, &Lingo.Cache.list_guilds/0)
      assert Lingo.with_bot(BetaBot, &Lingo.Cache.list_guilds/0) == []

      assert {:ok, _user} = Lingo.with_bot(BetaBot, fn -> Lingo.Api.User.get("1") end)
      assert_receive {:request, :get, "/api/v10/users/1", "Bot token-b", _body}
    end

    test "calls need a bot picked when more than one runs" do
      start_bot(AlphaBot, "token-a")
      start_bot(BetaBot, "token-b")

      assert_raise ArgumentError, ~r/several Lingo bots are running/, fn ->
        Lingo.Api.User.get("1")
      end

      Lingo.put_bot(AlphaBot)
      assert {:ok, _user} = Lingo.Api.User.get("1")
      assert_receive {:request, :get, "/api/v10/users/1", "Bot token-a", _body}
    end

    test "tasks act for the bot of the process that started them" do
      start_bot(AlphaBot, "token-a")
      start_bot(BetaBot, "token-b")
      Lingo.put_bot(BetaBot)

      Task.async(fn -> Lingo.Api.User.get("2") end) |> Task.await()
      assert_receive {:request, :get, "/api/v10/users/2", "Bot token-b", _body}
    end

    test "with one bot running, calls go to it" do
      start_bot(AlphaBot, "token-a")
      start_bot(BetaBot, "token-b")
      stop_supervised!(BetaBot)

      assert Lingo.bots() == [AlphaBot]
      assert {:ok, _user} = Lingo.Api.User.get("3")
      assert_receive {:request, :get, "/api/v10/users/3", "Bot token-a", _body}
    end

    test "without a bot running, calls raise" do
      assert_raise ArgumentError, ~r/no Lingo bot is running/, fn -> Lingo.Api.User.get("1") end
    end
  end

  describe "register_commands/1" do
    test "fetches the application id once, then replaces the commands" do
      start_bot(AlphaBot, "token-a")

      assert {:ok, [command]} = Lingo.register_commands()
      assert command.name == "ping"
      assert_receive {:request, :get, "/api/v10/applications/@me", _auth, _body}
      assert_receive {:request, :put, "/api/v10/applications/app1/commands", _auth, _body}

      assert {:ok, _commands} = Lingo.register_commands({:guild, "g1"})
      refute_receive {:request, :get, "/api/v10/applications/@me", _auth, _body}
      assert_receive {:request, :put, "/api/v10/applications/app1/guilds/g1/commands", _, _}
    end

    test "registers for several guilds" do
      start_bot(AlphaBot, "token-a")

      assert {:ok, [_, _]} = Lingo.register_commands({:guilds, ["g1", "g2"]})
      assert_receive {:request, :put, "/api/v10/applications/app1/guilds/g1/commands", _, _}
      assert_receive {:request, :put, "/api/v10/applications/app1/guilds/g2/commands", _, _}
    end

    test "runs when the bot is ready, if asked to" do
      start_bot(AlphaBot, "token-a", register_commands: :global)

      Lingo.with_bot(AlphaBot, fn -> Lingo.Gateway.Dispatcher.dispatch(:ready, %{}) end)
      assert_receive {:request, :put, "/api/v10/applications/app1/commands", _auth, _body}
    end
  end
end
