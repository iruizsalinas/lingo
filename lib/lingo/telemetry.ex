defmodule Lingo.Telemetry do
  @moduledoc """
  Telemetry events Lingo emits, for metrics and alerts: what happens inside
  Lingo, as opposed to the Discord events a bot handles (see `Lingo.Event`).

  Events go out through [`:telemetry`](https://hex.pm/packages/telemetry),
  an optional dependency: Lingo uses it when your application has it
  (Phoenix and most metrics libraries bring it), and without it emits
  nothing and costs nothing. Add `{:telemetry, "~> 1.0"}` to your deps
  to get them otherwise. What needs acting on is logged either way: a shard
  stopped for good, the daily identify limit spent, a global API rate limit.

  Every event's metadata includes `:bot`, the bot's name. Durations are in
  native time units (`System.convert_time_unit/3`); waits and latencies are
  in milliseconds.

  ## Spans

  Spans follow `:telemetry.span/3`: a `:start` event (measurements
  `:system_time` and `:monotonic_time`), then `:stop` (`:duration` and
  `:monotonic_time`) or, when it raises or exits, `:exception` (the same,
  with `:kind`, `:reason` and `:stacktrace` added to the metadata).

    * `[:lingo, :rest, :request, ...]` - one HTTP exchange with the API.
      Metadata: `:method`, `:path`; on `:stop`, `:status` too (`nil` on a
      transport error).
    * `[:lingo, :command, ...]` - a command's handler, checks included.
      Metadata: `:command_name`, `:type` (`:chat_input`, `:user`,
      `:message` or `:primary_entry_point`), `:guild_id`, `:user_id`.
    * `[:lingo, :event, ...]` - a `c:Lingo.Bot.handle_event/2` call.
      Metadata: `:event`.

  ## Events

    * `[:lingo, :command, :check_failed]` - a command didn't pass its
      checks, or is on cooldown. Metadata: `:command_name`, `:reason` (see
      `Lingo.CheckError`).
    * `[:lingo, :event, :parse_failed]` - an event Lingo couldn't parse,
      which goes to `c:Lingo.Bot.handle_error/2` as a `Lingo.EventError`.
      Metadata: `:event`.
    * `[:lingo, :shard, :ready]` - a shard's session started or resumed.
      Metadata: `:shard_id`, `:shard_count`, `:resumed`.
    * `[:lingo, :shard, :disconnected]` - a shard's connection closed.
      Metadata: `:shard_id`, `:shard_count`, `:code` (`nil` when the socket
      dropped without a close code), `:fatal` (`true` when the shard stops
      for good, such as for an invalid token or disallowed intents).
    * `[:lingo, :shard, :reconnecting]` - a shard will connect again.
      Measurements: `:delay`. Metadata: `:shard_id`, `:shard_count`.
    * `[:lingo, :gateway, :ready]` - every shard on this node connected,
      once at startup (see `Lingo.Gateway.await_ready/1`). Metadata:
      `:shard_count`.
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
    * `[:lingo, :rest, :rate_limited]` - the API answered 429. Measurements:
      `:retry_after`. Metadata: `:method`, `:path`, `:global`.
  """

  # Chosen when Lingo compiles: an optional dependency the application has
  # is compiled first, so it's loaded by now if it's there at all.
  if Code.ensure_loaded?(:telemetry) do
    @doc false
    @spec execute([atom()], map(), map()) :: :ok
    def execute(event, measurements, metadata \\ %{}) do
      :telemetry.execute([:lingo | event], measurements, with_bot(metadata))
    rescue
      # :telemetry is there but its application isn't started
      ArgumentError -> :ok
    end
  else
    @doc false
    @spec execute([atom()], map(), map()) :: :ok
    def execute(_event, _measurements, _metadata \\ %{}), do: :ok
  end

  @doc false
  # Runs `fun` as a span. `fun` returns `{result, stop_metadata}`; the stop
  # metadata is added to the start's. Exceptions, exits and throws emit
  # :exception and are raised again, as :telemetry.span/3 does.
  @spec span([atom()], map(), (-> {result, map()})) :: result when result: term()
  def span(event, metadata, fun) do
    metadata = with_bot(metadata)
    start = System.monotonic_time()

    execute(
      event ++ [:start],
      %{system_time: System.system_time(), monotonic_time: start},
      metadata
    )

    try do
      fun.()
    catch
      kind, reason ->
        stop = System.monotonic_time()
        meta = Map.merge(metadata, %{kind: kind, reason: reason, stacktrace: __STACKTRACE__})
        execute(event ++ [:exception], %{duration: stop - start, monotonic_time: stop}, meta)
        :erlang.raise(kind, reason, __STACKTRACE__)
    else
      {result, stop_metadata} ->
        stop = System.monotonic_time()
        measurements = %{duration: stop - start, monotonic_time: stop}
        execute(event ++ [:stop], measurements, Map.merge(metadata, stop_metadata))
        result
    end
  end

  defp with_bot(metadata), do: Map.put_new_lazy(metadata, :bot, &bot/0)

  defp bot do
    Lingo.Instance.current()
  rescue
    ArgumentError -> nil
  end
end
