defmodule Lingo.Test.Peer do
  @moduledoc false

  # Another node for tests of a bot spread across nodes. Code runs there by
  # module and function (test modules aren't on the peer's code path), so
  # the pieces of a bot a test needs are started from here.

  alias Lingo.Instance

  def start do
    args = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])
    # not linked: setup_all's process exits once it's done
    {:ok, peer, node} = :peer.start(%{name: :peer.random_name(), args: args})
    {:ok, _} = :erpc.call(node, Application, :ensure_all_started, [:lingo])
    {peer, node}
  end

  @doc "The pieces of a bot a cluster test needs, here or on the peer."
  def children(name) do
    [
      {Instance, name: name, token: "token-#{name}"},
      {Task.Supervisor, name: Instance.process_name(name, Lingo.TaskSupervisor)},
      {Lingo.Cache.Tables, bot: name, config: [guilds: true, channels: true]},
      {Lingo.Rest.RateLimiter, bot: name},
      {Lingo.Gateway.Groups, bot: name},
      {Lingo.Gateway.Identify,
       bot: name, plan: %{max_concurrency: 1, remaining: 1_000, reset_after: 60_000}}
    ]
  end

  # runs on the peer: started unlinked, so it outlives the :erpc call
  def start_bot(name, shard_count) do
    {:ok, sup} = Supervisor.start_link(children(name), strategy: :one_for_one)
    Process.unlink(sup)
    Instance.put(name, :shard_count, shard_count)
    sup
  end

  @doc "A process on this node in one of the bot's groups, forwarding what it gets to `to`."
  def member(name, group, to) do
    test = self()

    pid =
      spawn(fn ->
        :pg.join(Instance.process_name(name, Lingo.Gateway.Groups), group, self())
        send(test, {:joined, self()})
        forward(to)
      end)

    receive do
      {:joined, ^pid} -> pid
    end
  end

  defp forward(to) do
    receive do
      message -> send(to, {:peer_got, message})
    end

    forward(to)
  end

  def put_guild(name, id, guild_name),
    do:
      in_bot(name, fn ->
        Lingo.Cache.Store.put_guild(%Lingo.Type.Guild{id: id, name: guild_name})
      end)

  def reserve(name, shard_id),
    do: in_bot(name, fn -> Lingo.Gateway.Identify.reserve(shard_id) end)

  def wait_time(name, route), do: in_bot(name, fn -> Lingo.Rest.Buckets.wait_time(route) end)

  def in_bot(name, fun), do: Instance.with_current(name, fun)
end
