defmodule Lingo.Telemetry do
  @moduledoc """
  Telemetry events Lingo emits, for metrics and alerts.

  Lingo has no dependencies, so events go out through
  [`:telemetry`](https://hex.pm/packages/telemetry) only when your
  application already has it (Phoenix and most metrics libraries bring it).
  Without it they cost nothing.

  Every event's metadata includes `:bot`, the bot's name. Durations are in
  native time units; waits and latencies are in milliseconds.

    * `[:lingo, :shard, :ready]` - a shard's session started or resumed.
      Metadata: `:shard_id`, `:shard_count`, `:resumed`.
    * `[:lingo, :shard, :disconnected]` - a shard's connection closed.
      Metadata: `:shard_id`, `:shard_count`, `:code` (`nil` when the socket
      dropped without a close code).
    * `[:lingo, :shard, :identify]` - a shard identified. Measurements:
      `:wait`, how long it waited for its identify slot. Metadata:
      `:shard_id`, `:shard_count`.
    * `[:lingo, :shard, :heartbeat]` - a heartbeat was acknowledged.
      Measurements: `:latency`. Metadata: `:shard_id`.
    * `[:lingo, :gateway, :identify_limited]` - the daily identify limit is
      used up and a shard waits for it to reset. Measurements: `:wait`.
      Metadata: `:shard_id`.
    * `[:lingo, :gateway, :reshard, :start]` and
      `[:lingo, :gateway, :reshard, :stop]` - a reshard began, and the new
      shards took over. Measurements (stop): `:duration`. Metadata: `:from`
      and `:to`, the shard counts.
    * `[:lingo, :rest, :request]` - one HTTP exchange with the API.
      Measurements: `:duration`. Metadata: `:method`, `:path`, `:status`
      (`nil` on a transport error).
    * `[:lingo, :rest, :rate_limited]` - the API answered 429. Measurements:
      `:retry_after`. Metadata: `:method`, `:path`, `:global`.
  """

  @doc false
  @spec execute([atom()], map(), map()) :: :ok
  def execute(event, measurements, metadata \\ %{}) do
    if available?() do
      metadata = Map.put_new_lazy(metadata, :bot, &bot/0)

      try do
        apply(:telemetry, :execute, [[:lingo | event], measurements, metadata])
      rescue
        # the module is there but its application isn't started
        ArgumentError -> :ok
      end
    end

    :ok
  end

  # looked up once: the lookup searches the code path when the module is missing
  defp available? do
    case :persistent_term.get({__MODULE__, :available}, nil) do
      nil ->
        available = Code.ensure_loaded?(:telemetry)
        :persistent_term.put({__MODULE__, :available}, available)
        available

      available ->
        available
    end
  end

  defp bot do
    Lingo.Instance.current()
  rescue
    ArgumentError -> nil
  end
end
