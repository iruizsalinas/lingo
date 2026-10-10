defmodule Lingo.Gateway.ShardManagerTest do
  use ExUnit.Case, async: true

  alias Lingo.Gateway.{Groups, Shard, ShardManager}
  alias Lingo.Gateway.ShardManager.Pool
  alias Lingo.Test.FakeGateway

  defmodule GatewayBot do
    use Lingo.Bot

    @impl true
    def handle_event(event, data) do
      if pid = Process.whereis(Module.concat(Lingo.Instance.current(), Test)),
        do: send(pid, {:event, event, data})
    end
  end

  setup do
    gateway = FakeGateway.start(self())
    {:ok, plan} = Agent.start_link(fn -> %{shards: 1, remaining: 1_000} end)
    name = Module.concat(__MODULE__, "Bot#{System.unique_integer([:positive])}")
    Process.register(self(), Module.concat(name, Test))
    %{gateway: gateway, plan: plan, name: name}
  end

  defp start_bot(ctx, opts \\ []) do
    opts =
      [name: ctx.name, bot: GatewayBot, token: "token", http_request: http(ctx.gateway, ctx.plan)] ++
        opts

    start_supervised!(%{
      id: ctx.name,
      start: {Lingo.Supervisor, :start_link, [opts]},
      type: :supervisor
    })
  end

  # stands in for Discord's REST API
  defp http(gateway, plan) do
    fn :get, url, _headers, _body ->
      body =
        case URI.parse(url).path do
          "/api/v10/gateway/bot" ->
            %{shards: shards, remaining: remaining} = Agent.get(plan, & &1)

            %{
              "url" => gateway.url,
              "shards" => shards,
              "session_start_limit" => %{
                "total" => 1_000,
                "remaining" => remaining,
                "reset_after" => 60_000,
                "max_concurrency" => 16
              }
            }

          "/api/v10/users/@me" ->
            %{"id" => "100", "username" => "lingo"}
        end

      {:ok,
       %{status: 200, headers: [{"content-type", "application/json"}], body: JSON.encode!(body)}}
    end
  end

  defp typing(conn, channel_id),
    do: FakeGateway.dispatch(conn, "TYPING_START", %{channel_id: channel_id, user_id: "2"})

  defp manager_state(name),
    do: :sys.get_state(Lingo.Instance.process_name(name, ShardManager))

  defp in_bot(ctx, fun), do: Lingo.with_bot(ctx.name, fun)

  describe "starting" do
    test "starts every shard and fires :ready once all are up", ctx do
      Agent.update(ctx.plan, &%{&1 | shards: 2})
      start_bot(ctx)

      assert_receive {:identified, _, 0, 2}, 5_000
      assert_receive {:identified, _, 1, 2}, 5_000
      assert_receive {:event, :ready, %{shard_count: 2}}, 5_000
      assert in_bot(ctx, &Lingo.Gateway.shard_count/0) == 2
    end

    for encoding <- [:json, :etf], compression <- [:zlib, :zstd, :none] do
      test "delivers events over #{encoding} with #{compression} compression", ctx do
        start_bot(ctx, gateway: [encoding: unquote(encoding), compression: unquote(compression)])

        assert_receive {:identified, conn, 0, 1}, 5_000
        assert_receive {:event, :ready, _}, 5_000

        typing(conn, "123456789012345678")

        assert_receive {:event, :typing_start,
                        %{"channel_id" => "123456789012345678", "user_id" => "2"}},
                       5_000
      end
    end
  end

  describe "sessions" do
    test "a crashed connection resumes where it left off", ctx do
      start_bot(ctx)
      assert_receive {:identified, conn, 0, 1}, 5_000
      assert_receive {:event, :ready, _}, 5_000

      typing(conn, "1")
      typing(conn, "2")
      assert_receive {:event, :typing_start, %{"channel_id" => "2"}}, 5_000

      %{current: %{shards: %{0 => shard}}} = manager_state(ctx.name)
      Process.exit(Shard.connection(shard), :kill)

      # READY was 1, the two dispatches 2 and 3
      assert_receive {:resumed, _conn, "s0-1-" <> _, 3}, 5_000
      refute_received {:identified, _, 0, 1}
    end

    test "restart_shard/1 identifies from scratch", ctx do
      start_bot(ctx)
      assert_receive {:identified, _conn, 0, 1}, 5_000
      assert_receive {:event, :ready, _}, 5_000

      assert in_bot(ctx, fn -> Lingo.Gateway.restart_shard(0) end) == :ok
      # bucket 0 identified moments ago, so this one waits its 5 seconds
      assert_receive {:identified, _conn, 0, 1}, 10_000
      refute_received {:resumed, _, _, _}
    end

    @tag :tmp_dir
    test "a session store carries sessions over a full restart", %{tmp_dir: dir} = ctx do
      store = {Lingo.Gateway.SessionStore.File, path: Path.join(dir, "sessions")}
      start_bot(ctx, sharding: [session_store: store])
      assert_receive {:identified, conn, 0, 1}, 5_000
      assert_receive {:event, :ready, _}, 5_000
      typing(conn, "1")
      assert_receive {:event, :typing_start, _}, 5_000

      stop_supervised!(ctx.name)

      assert [%{shard_id: 0, shard_count: 1, seq: 2, session_id: session}] =
               Lingo.Gateway.SessionStore.File.load(ctx.name, path: Path.join(dir, "sessions"))

      start_bot(ctx, sharding: [session_store: store])
      assert_receive {:resumed, _conn, ^session, 2}, 5_000
      assert_receive {:event, :ready, %{shard_count: 1}}, 5_000
    end
  end

  describe "resharding" do
    @describetag :capture_log

    test "new shards take over only once all are ready", ctx do
      start_bot(ctx)
      assert_receive {:identified, old, 0, 1}, 5_000
      assert_receive {:event, :ready, _}, 5_000

      FakeGateway.auto_ready(ctx.gateway, false)
      Agent.update(ctx.plan, &%{&1 | shards: 2})
      in_bot(ctx, &Lingo.Gateway.reshard/0)

      # shares bucket 0 with the old shard 0, so waits its 5 seconds
      assert_receive {:identified, new0, 0, 2}, 10_000
      assert_receive {:identified, new1, 1, 2}, 5_000
      FakeGateway.ready(new0)

      # the old shard still delivers, the ready new one doesn't yet
      typing(new0, "new")
      typing(old, "old")
      assert_receive {:event, :typing_start, %{"channel_id" => "old"}}, 5_000
      refute_receive {:event, :typing_start, %{"channel_id" => "new"}}, 200
      assert in_bot(ctx, &Lingo.Gateway.shard_count/0) == 1

      FakeGateway.ready(new1)
      assert_receive {:closed, ^old}, 5_000
      assert in_bot(ctx, &Lingo.Gateway.shard_count/0) == 2

      typing(new0, "new")
      assert_receive {:event, :typing_start, %{"channel_id" => "new"}}, 5_000
      # :ready fires once, at startup
      refute_received {:event, :ready, _}
    end

    test "does nothing when the count is already right", ctx do
      start_bot(ctx)
      assert_receive {:identified, _conn, 0, 1}, 5_000
      assert_receive {:event, :ready, _}, 5_000

      in_bot(ctx, &Lingo.Gateway.reshard/0)
      assert %{next: nil, current: %Pool{count: 1}} = manager_state(ctx.name)
      refute_receive {:identified, _, _, _}, 200
    end
  end

  test "payloads for a shard this node doesn't run reach the node that does" do
    bot = Lingo.TestBot.start()
    start_supervised!({Groups, bot: bot})

    # shard 1 of 2 runs "elsewhere": a process in its group
    test_pid = self()

    spawn_link(fn ->
      Groups.join_shard(bot, 1, 2)
      send(test_pid, :joined)
      receive(do: (message -> send(test_pid, {:remote, message})))
    end)

    assert_receive :joined
    state = %ShardManager{bot: bot, current: %Pool{count: 2}}
    # guild ids whose shard (id >> 22 rem 2) is 1
    guild_id = Integer.to_string(Bitwise.bsl(1, 22))

    {:noreply, _state} =
      ShardManager.handle_cast({:send_to_guild_shard, guild_id, %{"op" => 8}}, state)

    assert_receive {:remote, {:"$gen_cast", {:send, %{"op" => 8}}}}
  end
end
