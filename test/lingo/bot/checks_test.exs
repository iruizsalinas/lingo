defmodule Lingo.Bot.ChecksTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Lingo.{CheckError, Context, Permissions}
  alias Lingo.Type.Interaction

  defmodule GuardedBot do
    use Lingo.Bot

    command("guild", "Guild only", checks: [:guild_only])

    command("ban", "Bans",
      checks: [{:permissions, [:ban_members]}, {:bot_permissions, [:ban_members]}]
    )

    command("custom", "Custom", checks: [&GuardedBot.even_user?/1])
    command("slow", "Cooldown", checks: [:guild_only], cooldown: {1, 60_000})
    command("owner", "Owners", checks: [:owner_only])
    user_command("Inspect", checks: [:guild_only])
    command("okcheck", "Passes with :ok", checks: [&GuardedBot.ok_check/1])
    command("badcheck", "Returns nonsense", checks: [&GuardedBot.bad_check/1])
    command("kw", "Keyword cooldown", cooldown: [uses: 1, per: 60_000, scope: :global])
    command("dyn", "Function cooldown", cooldown: &GuardedBot.cooldown/1)
    command("brief", "Short cooldown", cooldown: {1, 50})
    user_command("slow", cooldown: {1, 60_000})

    def even_user?(ctx),
      do: rem(String.to_integer(ctx.user_id), 2) == 0 || {:error, "Odd users can't."}

    def ok_check(_ctx), do: :ok
    def bad_check(_ctx), do: :maybe

    # owners skip it
    def cooldown(%{user_id: "1"}), do: nil
    def cooldown(_ctx), do: {1, 60_000}

    @impl true
    def handle_command(name, _ctx), do: report({:ran, name})

    @impl true
    def handle_component("crash", _ctx), do: raise("boom")
    def handle_component("exit", _ctx), do: exit(:gone)

    @impl true
    def handle_event(:crash, _data), do: raise(ArgumentError, "bad event")

    @impl true
    def handle_error(error, source), do: report({:error, error, source})

    defp report(message), do: send(Lingo.Instance.get(:test_pid), message)
  end

  defmodule PlainBot do
    use Lingo.Bot

    command("guild", "Guild only", checks: [:guild_only])

    @impl true
    def handle_command(name, _ctx), do: send(Lingo.Instance.get(:test_pid), {:ran, name})
  end

  defp start(bot) do
    test_pid = self()

    http = fn method, url, _headers, body ->
      path = URI.parse(url).path
      send(test_pid, {:rest, method, path, body})

      case path do
        "/api/v10/applications/@me" ->
          team = %{
            "owner_user_id" => "7",
            "members" => [
              %{"user" => %{"id" => "8"}, "role" => "read_only"},
              %{"user" => %{"id" => "9"}, "role" => "developer"},
              # from before team roles
              %{"user" => %{"id" => "10"}}
            ]
          }

          json(200, %{"id" => "2", "owner" => %{"id" => "1"}, "team" => team})

        _ ->
          {:ok, %{status: 204, headers: [], body: ""}}
      end
    end

    Lingo.TestBot.start(
      bot: bot,
      test_pid: test_pid,
      http_request: http,
      start: [:rate_limiter, :cooldowns]
    )
  end

  defp json(status, body),
    do:
      {:ok,
       %{
         status: status,
         headers: [{"content-type", "application/json"}],
         body: JSON.encode!(body)
       }}

  defp command(name, opts \\ []) do
    member_perms = Keyword.get(opts, :permissions, Permissions.from_list([]))

    base = %{
      "id" => "1",
      "application_id" => "2",
      "type" => 2,
      "token" => "t",
      "channel_id" => "50",
      "app_permissions" => to_string(Keyword.get(opts, :app_permissions, 0)),
      "data" => %{"id" => "3", "name" => name, "type" => Keyword.get(opts, :command_type, 1)}
    }

    user = %{"id" => Keyword.get(opts, :user_id, "4"), "username" => "u"}

    payload =
      if Keyword.get(opts, :guild, true),
        do:
          Map.merge(base, %{
            "guild_id" => "60",
            "member" => %{"user" => user, "roles" => [], "permissions" => to_string(member_perms)}
          }),
        else: Map.put(base, "user", user)

    Interaction.new(payload)
  end

  test "commands that pass their checks run" do
    start(GuardedBot)
    Lingo.Bot.Runner.interaction(command("guild"))
    assert_receive {:ran, "guild"}
  end

  test "a failed check goes to handle_error/2 instead of the handler" do
    start(GuardedBot)
    Lingo.Bot.Runner.interaction(command("guild", guild: false))

    assert_receive {:error, %CheckError{reason: :guild_only}, %Context{command_name: "guild"}}
    refute_received {:ran, _}
  end

  test "without handle_error/2, a failed check is answered ephemerally" do
    start(PlainBot)
    Lingo.Bot.Runner.interaction(command("guild", guild: false))

    assert_receive {:rest, :post, "/api/v10/interactions/1/t/callback", {_type, body}}

    assert %{"type" => 4, "data" => %{"flags" => 64, "content" => content}} =
             body |> IO.iodata_to_binary() |> JSON.decode!()

    assert content =~ "server"
    refute_received {:ran, _}
  end

  test "member and bot permissions, with Administrator granting all" do
    start(GuardedBot)
    ban = Permissions.from_list([:ban_members])

    Lingo.Bot.Runner.interaction(command("ban", permissions: 0, app_permissions: ban))
    assert_receive {:error, %CheckError{reason: {:missing_permissions, [:ban_members]}}, _}

    Lingo.Bot.Runner.interaction(command("ban", permissions: ban, app_permissions: 0))
    assert_receive {:error, %CheckError{reason: {:bot_missing_permissions, [:ban_members]}}, _}

    admin = Permissions.from_list([:administrator])
    Lingo.Bot.Runner.interaction(command("ban", permissions: admin, app_permissions: ban))
    assert_receive {:ran, "ban"}
  end

  test "custom checks can explain themselves" do
    start(GuardedBot)

    Lingo.Bot.Runner.interaction(command("custom", user_id: "5"))
    assert_receive {:error, %CheckError{reason: {:check, _}, message: "Odd users can't."}, _}

    Lingo.Bot.Runner.interaction(command("custom", user_id: "6"))
    assert_receive {:ran, "custom"}
  end

  test "cooldowns count per user, and failed checks don't use them up" do
    start(GuardedBot)

    Lingo.Bot.Runner.interaction(command("slow", guild: false))
    assert_receive {:error, %CheckError{reason: :guild_only}, _}

    Lingo.Bot.Runner.interaction(command("slow"))
    assert_receive {:ran, "slow"}

    Lingo.Bot.Runner.interaction(command("slow"))
    assert_receive {:error, %CheckError{reason: {:cooldown, wait}}, _}
    assert wait > 59_000

    Lingo.Bot.Runner.interaction(command("slow", user_id: "7"))
    assert_receive {:ran, "slow"}
  end

  test "owner_only allows the team's owner, admins and developers" do
    start(GuardedBot)

    for user_id <- ["7", "9", "10"] do
      Lingo.Bot.Runner.interaction(command("owner", user_id: user_id))
      assert_receive {:ran, "owner"}
    end

    # read-only members, and the team's stand-in owner user
    for user_id <- ["8", "1"] do
      Lingo.Bot.Runner.interaction(command("owner", user_id: user_id))
      assert_receive {:error, %CheckError{reason: :owner_only}, _}
    end
  end

  test "permission checks outside a guild fail as guild_only" do
    start(GuardedBot)
    Lingo.Bot.Runner.interaction(command("ban", guild: false))
    assert_receive {:error, %CheckError{reason: :guild_only}, _}
  end

  @tag :capture_log
  test "custom checks pass with :ok, and raise on anything else" do
    start(GuardedBot)

    Lingo.Bot.Runner.interaction(command("okcheck"))
    assert_receive {:ran, "okcheck"}

    Lingo.Bot.Runner.interaction(command("badcheck"))
    assert_receive {:error, %ArgumentError{message: message}, %Context{}}
    assert message =~ "returned :maybe"
    refute_received {:ran, "badcheck"}
  end

  test "cooldowns as keywords, functions, and per command type" do
    start(GuardedBot)

    # global: another user waits too
    Lingo.Bot.Runner.interaction(command("kw", user_id: "4"))
    assert_receive {:ran, "kw"}
    Lingo.Bot.Runner.interaction(command("kw", user_id: "5"))
    assert_receive {:error, %CheckError{reason: {:cooldown, _}}, _}

    # the function lets user 1 through every time
    for _ <- 1..2 do
      Lingo.Bot.Runner.interaction(command("dyn", user_id: "1"))
      assert_receive {:ran, "dyn"}
    end

    Lingo.Bot.Runner.interaction(command("dyn", user_id: "4"))
    assert_receive {:ran, "dyn"}
    Lingo.Bot.Runner.interaction(command("dyn", user_id: "4"))
    assert_receive {:error, %CheckError{reason: {:cooldown, _}}, _}

    # a user command and a slash command with the same name count apart
    Lingo.Bot.Runner.interaction(command("slow"))
    assert_receive {:ran, "slow"}
    Lingo.Bot.Runner.interaction(command("slow", command_type: 2))
    assert_receive {:ran, "slow"}
  end

  test "a cooldown's window opens again once it has passed" do
    start(GuardedBot)

    Lingo.Bot.Runner.interaction(command("brief"))
    assert_receive {:ran, "brief"}
    Lingo.Bot.Runner.interaction(command("brief"))
    assert_receive {:error, %CheckError{reason: {:cooldown, wait}}, _}
    assert wait <= 50

    Process.sleep(60)
    Lingo.Bot.Runner.interaction(command("brief"))
    assert_receive {:ran, "brief"}
  end

  test "context menu commands have their own checks" do
    start(GuardedBot)
    Lingo.Bot.Runner.interaction(command("Inspect", command_type: 2, guild: false))
    assert_receive {:error, %CheckError{reason: :guild_only}, %Context{command_name: "Inspect"}}
  end

  test "crashes are logged and handed to handle_error/2" do
    start(GuardedBot)

    log =
      capture_log(fn ->
        component =
          Interaction.new(%{
            "id" => "1",
            "application_id" => "2",
            "type" => 3,
            "token" => "t",
            "user" => %{"id" => "4"},
            "data" => %{"custom_id" => "crash", "component_type" => 2}
          })

        Lingo.Bot.Runner.interaction(component)
        assert_receive {:error, %RuntimeError{message: "boom"}, %Context{custom_id: "crash"}}

        Lingo.Bot.Runner.interaction(%{
          component
          | data: %{"custom_id" => "exit", "component_type" => 2}
        })

        assert_receive {:error, %ErlangError{original: {:exit, :gone}}, %Context{}}

        Lingo.Bot.Runner.event(:crash, :payload)
        assert_receive {:error, %ArgumentError{}, {:crash, :payload}}
      end)

    assert log =~ "boom"
    assert log =~ "event :crash"
  end

  test "checks and cooldowns are validated when the bot compiles" do
    assert_raise ArgumentError, ~r/invalid check/, fn ->
      Lingo.Bot.Commands.__rules__(:chat_input, "x", checks: [fn _ -> true end])
    end

    assert_raise ArgumentError, ~r/invalid check/, fn ->
      Lingo.Bot.Commands.__rules__(:chat_input, "x", checks: [:admins])
    end

    assert_raise ArgumentError, ~r/cooldown/, fn ->
      Lingo.Bot.Commands.__rules__(:chat_input, "x", cooldown: {1, 1_000, :planet})
    end

    assert_raise ArgumentError, ~r/cooldown/, fn ->
      Lingo.Bot.Commands.__rules__(:chat_input, "x", cooldown: [uses: 1, every: 1_000])
    end

    assert_raise ArgumentError, ~r/capture/, fn ->
      Lingo.Bot.Commands.__rules__(:chat_input, "x", cooldown: fn _ -> nil end)
    end

    assert {_, %{cooldown: {2, 1_000, :guild}}} =
             Lingo.Bot.Commands.__rules__(:chat_input, "x",
               cooldown: [uses: 2, per: 1_000, scope: :guild]
             )

    assert Lingo.Bot.Commands.__rules__(:chat_input, "x", []) == nil
  end
end
