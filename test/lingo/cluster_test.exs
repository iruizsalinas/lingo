defmodule Lingo.ClusterTest do
  # a bot spread over this node and a peer: cache reads, payload routing and
  # identify limits across both
  use ExUnit.Case, async: true

  @moduletag :distributed

  alias Lingo.Gateway.{Groups, Identify, ShardManager}
  alias Lingo.Gateway.ShardManager.Pool
  alias Lingo.Test.Peer

  setup_all do
    {peer, node} = Peer.start()
    on_exit(fn -> :peer.stop(peer) end)
    :global.sync()
    %{node: node}
  end

  setup %{node: node} do
    name = Module.concat(__MODULE__, "Bot#{System.unique_integer([:positive])}")

    for child <- Peer.children(name),
        do: start_supervised!(Supervisor.child_spec(child, id: {name, child}))

    Lingo.Instance.put(name, :shard_count, 2)
    Lingo.put_bot(name)

    :erpc.call(node, Peer, :start_bot, [name, 2])
    # the peer runs shard 1 of 2, this node shard 0
    :erpc.call(node, Peer, :member, [name, :managers, self()])
    Peer.member(name, :managers, self())
    %{name: name, node: node}
  end

  # a guild id on shard 1 of 2
  @remote_guild Integer.to_string(Bitwise.bsl(1, 22))

  describe "cache" do
    test "with cluster: true, a miss is answered by the node running the guild's shard",
         %{name: name, node: node} do
      :erpc.call(node, Peer, :member, [name, {:shard, 2, 1}, self()])
      :erpc.call(node, Peer, :put_guild, [name, @remote_guild, "Over there"])

      assert %Lingo.Type.Guild{name: "Over there"} =
               Lingo.Cache.Guild.get(@remote_guild, cluster: true)

      assert Lingo.Cache.Guild.get("999", cluster: true) == nil
    end

    test "reads stay on this node by default", %{name: name, node: node} do
      :erpc.call(node, Peer, :member, [name, {:shard, 2, 1}, self()])
      :erpc.call(node, Peer, :put_guild, [name, @remote_guild, "Over there"])
      # a guild on shard 0, this node's
      Peer.put_guild(name, "1", "Here")

      assert Lingo.Cache.Guild.get(@remote_guild) == nil
      assert ["Here"] = Lingo.Cache.Guild.list() |> Enum.map(& &1.name)
    end

    test "lists gather every node's entries with cluster: true", %{name: name, node: node} do
      Peer.put_guild(name, "4194304", "Here")
      :erpc.call(node, Peer, :put_guild, [name, @remote_guild, "Over there"])

      assert ["Here", "Over there"] =
               Lingo.Cache.Guild.list(cluster: true) |> Enum.map(& &1.name) |> Enum.sort()
    end

    test "reads without a guild ask every other node with cluster: true",
         %{name: name, node: node} do
      :erpc.call(node, Peer, :put_guild, [name, @remote_guild, "Over there"])

      # the guild has no shard owner registered, so only the any-node path finds it
      assert Lingo.Cache.Cluster.any([], Lingo.Cache.Tables, :get, [:guilds, @remote_guild]) ==
               nil

      assert %Lingo.Type.Guild{name: "Over there"} =
               Lingo.Cache.Cluster.any([cluster: true], Lingo.Cache.Tables, :get, [
                 :guilds,
                 @remote_guild
               ])
    end
  end

  test "payloads for the peer's shard reach it", %{name: name, node: node} do
    :erpc.call(node, Peer, :member, [name, {:shard, 2, 1}, self()])
    # the peer's membership reaches this node's groups asynchronously
    assert is_pid(wait_for(fn -> Groups.shard(name, 1, 2) end))
    state = %ShardManager{bot: name, current: %Pool{count: 2}}

    {:noreply, _} =
      ShardManager.handle_cast({:send_to_guild_shard, @remote_guild, %{"op" => 8}}, state)

    assert_receive {:peer_got, {:"$gen_cast", {:send, %{"op" => 8}}}}, 2_000
  end

  test "presence updates reach every node's shard manager", %{name: name} do
    ShardManager.update_presence(status: :idle)

    # one from each node's stand-in manager
    assert_receive {:peer_got, {:"$gen_cast", {:update_presence, [status: :idle]}}}, 2_000
    assert_receive {:peer_got, {:"$gen_cast", {:update_presence, [status: :idle]}}}, 2_000
    _ = name
  end

  test "both nodes share one identify queue", %{name: name, node: node} do
    global = {Identify, name, :erlang.phash2("token-#{name}")}
    :global.sync()
    :erpc.call(node, :global, :sync, [])

    # both started as leaders before the names synced; one gave way
    assert [pid, pid] =
             wait_for(fn ->
               leaders =
                 for n <- [node(), node], do: :erpc.call(n, :global, :whereis_name, [global])

               if match?([same, same] when is_pid(same), leaders), do: leaders
             end)

    # shard 0 identifies here, shard 1 (same bucket) on the peer, which waits
    assert Identify.reserve(0) == {:ok, 0}
    assert {:ok, wait} = :erpc.call(node, Peer, :reserve, [name, 1])
    assert wait > 5_000
  end

  defp wait_for(fun, tries \\ 50) do
    case fun.() do
      nil when tries > 0 ->
        Process.sleep(20)
        wait_for(fun, tries - 1)

      result ->
        result
    end
  end

  test "the groups see members on both nodes", %{name: name} do
    assert name |> Groups.managers() |> Enum.map(&node/1) |> Enum.uniq() |> length() == 2
  end

  describe "rate limits" do
    test "a global pause holds the other nodes back too", %{name: name, node: node} do
      Lingo.Rest.Shared.pause(5_000)

      assert wait_for(fn ->
               if :erpc.call(node, Peer, :wait_time, [name, "any"]) > 4_000, do: true
             end)
    end

    test "an exhausted bucket is shared, one with requests left isn't", %{name: name, node: node} do
      headers = fn remaining ->
        [
          {"x-ratelimit-remaining", remaining},
          {"x-ratelimit-reset-after", "5"},
          {"x-ratelimit-limit", "5"},
          {"x-ratelimit-bucket", "abc"}
        ]
      end

      Lingo.Rest.Shared.bucket("get:/channels/1/messages", headers.("3"))
      Lingo.Rest.Shared.bucket("get:/channels/2/messages", headers.("0"))

      assert wait_for(fn ->
               if :erpc.call(node, Peer, :wait_time, [name, "get:/channels/2/messages"]) > 4_000,
                 do: true
             end)

      assert :erpc.call(node, Peer, :wait_time, [name, "get:/channels/1/messages"]) == 0
    end
  end
end
