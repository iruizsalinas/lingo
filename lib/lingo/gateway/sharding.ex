defmodule Lingo.Gateway.Sharding do
  @moduledoc false

  # Which shards to run, and which shard a guild belongs to.

  import Bitwise

  @type plan :: %{
          url: String.t(),
          recommended: pos_integer(),
          max_concurrency: pos_integer(),
          remaining: non_neg_integer(),
          reset_after: non_neg_integer()
        }

  @doc "Asks Discord where to connect and how many shards it recommends."
  @spec fetch() :: {:ok, plan()} | {:error, Lingo.Error.t()}
  def fetch do
    with {:ok, body} <- Lingo.Rest.Client.request(:get, "/gateway/bot") do
      limit = body["session_start_limit"] || %{}

      {:ok,
       %{
         url: String.trim_trailing(body["url"], "/"),
         recommended: body["shards"],
         max_concurrency: limit["max_concurrency"] || 1,
         remaining: limit["remaining"] || 1000,
         reset_after: limit["reset_after"] || 0
       }}
    end
  end

  @spec count(:auto | pos_integer(), pos_integer()) :: pos_integer()
  def count(:auto, recommended), do: recommended
  def count(count, _recommended) when is_integer(count), do: count

  @spec ids(:all | [non_neg_integer()], pos_integer()) :: [non_neg_integer()]
  def ids(:all, count), do: Enum.to_list(0..(count - 1))
  def ids(ids, _count) when is_list(ids), do: ids

  @spec shard_for(String.t(), non_neg_integer()) :: non_neg_integer()
  def shard_for(_guild_id, 0), do: 0

  def shard_for(guild_id, count) when is_binary(guild_id),
    do: rem(String.to_integer(guild_id) >>> 22, count)
end
