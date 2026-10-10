defmodule Lingo.Gateway.Heartbeat do
  @moduledoc false

  use GenServer

  defstruct [
    :latency_table,
    :interval,
    :connection,
    :shard_id,
    :timer_ref,
    :ack_received,
    :last_sent
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def ack(pid) do
    GenServer.cast(pid, :ack)
  end

  def latency(shard_id) do
    if table = Lingo.Instance.get(:latency_table) do
      case :ets.lookup(table, shard_id) do
        [{_, ms}] -> ms
        [] -> nil
      end
    end
  end

  def latencies do
    if table = Lingo.Instance.get(:latency_table), do: Map.new(:ets.tab2list(table)), else: %{}
  end

  @impl true
  def init(opts) do
    bot = opts[:bot]
    if bot, do: Lingo.Instance.put_current(bot)

    interval = Keyword.fetch!(opts, :interval)
    connection = Keyword.fetch!(opts, :connection)
    shard_id = Keyword.get(opts, :shard_id)

    jitter = :rand.uniform()
    first_delay = trunc(interval * jitter)
    timer_ref = Process.send_after(self(), :beat, first_delay)

    {:ok,
     %__MODULE__{
       latency_table: bot && Lingo.Instance.get(bot, :latency_table, nil),
       interval: interval,
       connection: connection,
       shard_id: shard_id,
       timer_ref: timer_ref,
       ack_received: true,
       last_sent: nil
     }}
  end

  @impl true
  def handle_cast(:ack, state) do
    if state.latency_table && state.last_sent && state.shard_id do
      ms = System.monotonic_time(:millisecond) - state.last_sent
      :ets.insert(state.latency_table, {state.shard_id, ms})
    end

    {:noreply, %{state | ack_received: true}}
  end

  @impl true
  def handle_info(:beat, %{ack_received: false} = state) do
    send(state.connection, :heartbeat_timeout)
    {:noreply, state}
  end

  def handle_info(:beat, state) do
    # the connection fills in its latest sequence number
    send(state.connection, :send_heartbeat)
    timer_ref = Process.send_after(self(), :beat, state.interval)

    {:noreply,
     %{
       state
       | ack_received: false,
         timer_ref: timer_ref,
         last_sent: System.monotonic_time(:millisecond)
     }}
  end
end
