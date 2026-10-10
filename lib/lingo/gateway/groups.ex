defmodule Lingo.Gateway.Groups do
  @moduledoc false

  # Finds a bot's shards across connected nodes, through a :pg scope named
  # after the bot (so the same bot on several nodes shares it):
  #
  #   * :managers - every node's shard manager
  #   * {:shard, count, id} - the live connection of a shard
  #
  # Connections join once they deliver events, so a reshard's new shards stay
  # out of the groups until they take over. Members leave when they exit.

  alias Lingo.Instance

  def child_spec(opts) do
    scope = scope(Keyword.fetch!(opts, :bot))
    %{id: __MODULE__, start: {:pg, :start_link, [scope]}}
  end

  @spec join_manager(term()) :: :ok
  def join_manager(bot), do: join(bot, :managers)

  @spec join_shard(term(), non_neg_integer(), pos_integer()) :: :ok
  def join_shard(bot, shard_id, count), do: join(bot, {:shard, count, shard_id})

  @spec managers(term()) :: [pid()]
  def managers(bot), do: members(bot, :managers)

  @doc "A shard's live connection, on this node if it runs here."
  @spec shard(term(), non_neg_integer(), pos_integer()) :: pid() | nil
  def shard(bot, shard_id, count) do
    group = {:shard, count, shard_id}

    case members(bot, group, :local) do
      [pid | _] -> pid
      [] -> List.first(members(bot, group))
    end
  end

  @doc "The other connected nodes running the bot."
  @spec other_nodes(term()) :: [node()]
  def other_nodes(bot),
    do: bot |> managers() |> Enum.map(&node/1) |> Enum.uniq() |> List.delete(node())

  @doc "Runs `module.fun(args)` for the bot on every other node, without waiting."
  @spec cast_others(term(), module(), atom(), list()) :: :ok
  def cast_others(bot, module, fun, args) do
    for node <- other_nodes(bot), do: :erpc.cast(node, __MODULE__, :run, [bot, module, fun, args])
    :ok
  end

  @doc false
  # what other nodes call: runs as the bot
  def run(bot, module, fun, args),
    do: Instance.with_current(bot, fn -> apply(module, fun, args) end)

  defp join(bot, group) do
    if running?(bot), do: :pg.join(scope(bot), group, self())
    :ok
  end

  defp members(bot, group, where \\ :cluster) do
    cond do
      not running?(bot) -> []
      where == :local -> :pg.get_local_members(scope(bot), group)
      true -> :pg.get_members(scope(bot), group)
    end
  end

  defp running?(bot), do: Process.whereis(scope(bot)) != nil

  defp scope(bot), do: Instance.process_name(bot, __MODULE__)
end
