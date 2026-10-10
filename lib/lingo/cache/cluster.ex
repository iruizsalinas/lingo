defmodule Lingo.Cache.Cluster do
  @moduledoc false

  # Cache reads across nodes. Each node caches what its own shards receive,
  # so when the bot runs on several connected nodes a local miss is asked of
  # the node running the guild's shard, or, for lookups that don't name a
  # guild (channels, users, messages), of the other nodes. On one node this
  # costs a process group lookup per miss.
  #
  # Gateway connections read only their own node's cache: what they look up
  # (the old version of what an event changes) belongs to their own shard.

  alias Lingo.Gateway.{Groups, Sharding}
  alias Lingo.Instance

  @timeout 2_000
  @local_only {__MODULE__, :local_only}

  @doc "Makes the calling process's cache reads local only."
  @spec local_only() :: :ok
  def local_only do
    Process.put(@local_only, true)
    :ok
  end

  @doc "A read of one guild's data: the local answer, or the owning node's."
  @spec guild(String.t(), module(), atom(), list()) :: term()
  def guild(guild_id, module, fun, args) do
    case apply(module, fun, args) do
      empty when empty in [nil, []] ->
        if local_only?(), do: empty, else: from_owner(guild_id, module, fun, args, empty)

      found ->
        found
    end
  end

  @doc "A read any node may answer: the first one that knows."
  @spec any(module(), atom(), list()) :: term()
  def any(module, fun, args) do
    case apply(module, fun, args) do
      empty when empty in [nil, []] ->
        if local_only?(), do: empty, else: from_others(module, fun, args, empty)

      found ->
        found
    end
  end

  @doc "A list read gathered from every node."
  @spec all(module(), atom(), list()) :: list()
  def all(module, fun, args) do
    bot = Instance.current()
    remote = if local_only?(), do: [], else: Groups.other_nodes(bot)

    remote_items =
      remote
      |> :erpc.multicall(Groups, :run, [bot, module, fun, args], @timeout)
      |> Enum.flat_map(fn
        {:ok, items} -> items
        _failed -> []
      end)

    apply(module, fun, args) ++ remote_items
  end

  defp local_only?, do: Process.get(@local_only, false)

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

  defp from_others(module, fun, args, empty) do
    bot = Instance.current()

    Enum.find_value(Groups.other_nodes(bot), empty, fn node ->
      case call(node, bot, module, fun, args) do
        {:ok, found} when found not in [nil, []] -> found
        _missing -> nil
      end
    end)
  end

  defp call(node, bot, module, fun, args) do
    {:ok, :erpc.call(node, Groups, :run, [bot, module, fun, args], @timeout)}
  catch
    _kind, _reason -> :error
  end
end
