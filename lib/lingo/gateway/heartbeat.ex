defmodule Lingo.Gateway.Heartbeat do
  @moduledoc false

  use GenServer

  @table :lingo_latency

  defstruct [:interval, :connection, :shard_id, :timer_ref, :ack_received, :seq, :last_sent]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def ack(pid) do
    GenServer.cast(pid, :ack)
  end

  def update_seq(pid, seq) do
    GenServer.cast(pid, {:update_seq, seq})
  end

  def latency(shard_id) do
    if :ets.whereis(@table) != :undefined do
      case :ets.lookup(@table, shard_id) do
        [{_, ms}] -> ms
        [] -> nil
      end
    end
  end

  def latencies do
    if :ets.whereis(@table) != :undefined do
      :ets.tab2list(@table) |> Map.new()
    else
      %{}
    end
  end

  @impl true
  def init(opts) do
    try do
      :ets.new(@table, [:named_table, :public, :set])
    rescue
      ArgumentError -> :ok
    end

    interval = Keyword.fetch!(opts, :interval)
    connection = Keyword.fetch!(opts, :connection)
    shard_id = Keyword.get(opts, :shard_id)

    jitter = :rand.uniform()
    first_delay = trunc(interval * jitter)
    timer_ref = Process.send_after(self(), :beat, first_delay)

    {:ok,
     %__MODULE__{
       interval: interval,
       connection: connection,
       shard_id: shard_id,
       timer_ref: timer_ref,
       ack_received: true,
       seq: nil,
       last_sent: nil
     }}
  end

  @impl true
  def handle_cast(:ack, state) do
    if state.last_sent && state.shard_id do
      ms = System.monotonic_time(:millisecond) - state.last_sent
      :ets.insert(@table, {state.shard_id, ms})
    end

    {:noreply, %{state | ack_received: true}}
  end

  def handle_cast({:update_seq, seq}, state) do
    {:noreply, %{state | seq: seq}}
  end

  @impl true
  def handle_info(:beat, %{ack_received: false} = state) do
    send(state.connection, :heartbeat_timeout)
    {:noreply, state}
  end

  def handle_info(:beat, state) do
    send(state.connection, {:send_heartbeat, state.seq})
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
