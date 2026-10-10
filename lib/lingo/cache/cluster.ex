defmodule Lingo.Cache.Cluster do
  @moduledoc false

  # Cache reads across nodes, for `cluster: true`. Each node caches what its
  # own shards receive, so when the bot runs on several connected nodes a
  # local miss can be asked of the node running the guild's shard, or, for
  # lookups that don't name a guild (channels, users, messages), of every
  # other node at once. Reads without `cluster: true` stay on this node.

  alias Lingo.Gateway.{Groups, Sharding}
  alias Lingo.Instance

  @timeout 2_000

  @doc "A read of one guild's data: the local answer, or the owning node's."
  @spec guild(String.t(), keyword(), module(), atom(), list()) :: term()
  def guild(guild_id, opts, module, fun, args) do
    case apply(module, fun, args) do
      empty when empty in [nil, []] ->
        if opts[:cluster], do: from_owner(guild_id, module, fun, args, empty), else: empty

      found ->
        found
    end
  end

  @doc "A read any node may answer: the local answer, or the first other node's."
  @spec any(keyword(), module(), atom(), list()) :: term()
  def any(opts, module, fun, args) do
    case apply(module, fun, args) do
      empty when empty in [nil, []] ->
        if opts[:cluster], do: from_others(module, fun, args, empty), else: empty

      found ->
        found
    end
  end

  @doc "A list read: this node's entries, and every other node's too."
  @spec all(keyword(), module(), atom(), list()) :: list()
  def all(opts, module, fun, args) do
    remote = if opts[:cluster], do: multicall(module, fun, args), else: []
    apply(module, fun, args) ++ Enum.concat(remote)
  end

  defp from_owner(guild_id, module, fun, args, empty) do
    bot = Instance.current()

    with [_ | _] <- Groups.other_nodes(bot),
         count when is_integer(count) and count > 0 <- Instance.get(bot, :shard_count, nil),
         pid when is_pid(pid) <- Groups.shard(bot, Sharding.shard_for(guild_id, count), count),
         true <- node(pid) != node(),
         {:ok, found} <- call(node(pid), bot, module, fun, args) do
      found
    else
      _local_or_unknown -> empty
    end
  end

  # every node at once; nodes that don't answer in time count as misses
  defp from_others(module, fun, args, empty) do
    module
    |> multicall(fun, args)
    |> Enum.find(empty, &(&1 not in [nil, []]))
  end

  defp multicall(module, fun, args) do
    bot = Instance.current()

    bot
    |> Groups.other_nodes()
    |> :erpc.multicall(Groups, :run, [bot, module, fun, args], @timeout)
    |> Enum.flat_map(fn
      {:ok, result} -> [result]
      _failed -> []
    end)
  end

  defp call(node, bot, module, fun, args) do
    {:ok, :erpc.call(node, Groups, :run, [bot, module, fun, args], @timeout)}
  catch
    _kind, _reason -> :error
  end
end
