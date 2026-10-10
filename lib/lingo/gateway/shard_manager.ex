defmodule Lingo.Gateway.ShardManager do
  @moduledoc false

  # Starts a bot's shards, restarts dead ones, routes payloads to the right
  # shard, paces identifies and fires :ready once every shard is up.

  use GenServer

  alias Lingo.Gateway.{Connection, Dispatcher, Intents, Shard, Sharding}
  alias Lingo.Gateway.ShardManager.Pool

  defstruct [
    :bot,
    :token,
    :intents,
    :shard_supervisor,
    :gateway_url,
    shard_count: 0,
    configured_count: :auto,
    configured_ids: :all,
    presence: [],
    shards: %{},
    shard_refs: %{},
    ready_shards: %{},
    ready_fired: false,
    expected_shard_count: 0,
    max_concurrency: 1,
    identify_slots: %{}
  ]

  # Discord allows max_concurrency identifies per 5 seconds, one per bucket
  @identify_interval_ms 5_500

  def start_link(opts) do
    bot = Keyword.fetch!(opts, :bot)
    GenServer.start_link(__MODULE__, opts, name: Lingo.Instance.process_name(bot, __MODULE__))
  end

  defp server, do: Lingo.Instance.process_name(__MODULE__)

  def broadcast(payload), do: GenServer.cast(server(), {:broadcast, payload})

  def send_to_shard(shard_id, payload),
    do: GenServer.cast(server(), {:send_to_shard, shard_id, payload})

  def send_to_guild_shard(guild_id, payload),
    do: GenServer.cast(server(), {:send_to_guild_shard, guild_id, payload})

  def update_presence(presence), do: GenServer.cast(server(), {:update_presence, presence})
  def shard_ready(shard_id), do: GenServer.cast(server(), {:shard_ready, shard_id})
  def reshard, do: GenServer.cast(server(), :reshard)
  def shard_for_guild(guild_id), do: GenServer.call(server(), {:shard_for_guild, guild_id})
  def shard_count, do: GenServer.call(server(), :shard_count)
  def shard_status(shard_id), do: GenServer.call(server(), {:shard_status, shard_id})
  def shard_statuses, do: GenServer.call(server(), :shard_statuses)
  def restart_shard(shard_id), do: GenServer.call(server(), {:restart_shard, shard_id}, 30_000)

  # Reserves the next identify slot for this shard's rate limit bucket and
  # returns how long to wait, in ms, before sending Identify.
  def reserve_identify(shard_id) do
    GenServer.call(server(), {:reserve_identify, shard_id}, 10_000)
  catch
    :exit, _ -> 0
  end

  @impl true
  def init(opts) do
    bot = Keyword.fetch!(opts, :bot)
    Lingo.Instance.put_current(bot)
    Lingo.Instance.put(bot, :latency_table, :ets.new(:latency, [:public, :set]))

    {:ok, shard_supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)
    sharding = opts[:sharding] || []

    send(self(), :start_shards)

    {:ok,
     %__MODULE__{
       bot: bot,
       token: Keyword.fetch!(opts, :token),
       intents: Intents.resolve(opts[:intents] || [:guilds, :guild_messages]),
       shard_supervisor: shard_supervisor,
       configured_count: Keyword.get(sharding, :count, :auto),
       configured_ids: Keyword.get(sharding, :ids, :all),
       presence: opts[:presence] || []
     }}
  end

  @impl true
  def handle_info(:start_shards, state) do
    case Sharding.fetch() do
      {:ok, %{remaining: remaining, recommended: recommended} = plan}
      when remaining < recommended ->
        Process.send_after(self(), :start_shards, plan.reset_after + 1_000)
        {:noreply, state}

      {:ok, plan} ->
        count = Sharding.count(state.configured_count, plan.recommended)
        {:noreply, Pool.start_all(state, plan, count)}

      {:error, _reason} ->
        Process.send_after(self(), :start_shards, 5_000)
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.shard_refs, ref) do
      {nil, _refs} ->
        {:noreply, state}

      {shard_id, refs} ->
        Process.send_after(self(), {:restart_dead_shard, shard_id}, 5_000)
        {:noreply, %{Pool.forget(state, shard_id) | shard_refs: refs}}
    end
  end

  def handle_info({:restart_dead_shard, shard_id}, state) do
    cond do
      Map.has_key?(state.shards, shard_id) ->
        {:noreply, state}

      true ->
        case Pool.start(state, shard_id) do
          {:ok, state} ->
            {:noreply, state}

          {:error, _reason} ->
            Process.send_after(self(), {:restart_dead_shard, shard_id}, 10_000)
            {:noreply, state}
        end
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def handle_cast({:broadcast, payload}, state) do
    Enum.each(state.shards, fn {_id, shard} -> Shard.send_payload(shard, payload) end)
    {:noreply, state}
  end

  def handle_cast({:send_to_shard, shard_id, payload}, state) do
    if shard = state.shards[shard_id], do: Shard.send_payload(shard, payload)
    {:noreply, state}
  end

  def handle_cast({:send_to_guild_shard, guild_id, payload}, state) do
    handle_cast({:send_to_shard, Sharding.shard_for(guild_id, state.shard_count), payload}, state)
  end

  # shards started later identify with the latest presence
  def handle_cast({:update_presence, presence}, state) do
    for {_id, shard} <- state.shards,
        pid = Shard.connection(shard),
        do: Connection.update_presence(pid, presence)

    {:noreply, %{state | presence: presence}}
  end

  def handle_cast({:shard_ready, shard_id}, state) do
    state = %{state | ready_shards: Map.put(state.ready_shards, shard_id, true)}

    if not state.ready_fired and map_size(state.ready_shards) == state.expected_shard_count do
      Dispatcher.dispatch(:ready, %{shard_count: state.shard_count})
      {:noreply, %{state | ready_fired: true}}
    else
      {:noreply, state}
    end
  end

  def handle_cast(:reshard, %{configured_count: count} = state) when is_integer(count),
    do: {:noreply, state}

  def handle_cast(:reshard, state) do
    case Sharding.fetch() do
      {:ok, %{remaining: remaining, recommended: recommended} = plan}
      when remaining >= recommended ->
        fresh = %{state | shards: %{}, shard_refs: %{}, ready_shards: %{}, ready_fired: false}
        new_state = Pool.start_all(fresh, plan, recommended)

        for {_id, old} <- state.shards,
            do: DynamicSupervisor.terminate_child(state.shard_supervisor, old)

        {:noreply, new_state}

      _not_now ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:reserve_identify, shard_id}, _from, state) do
    now = System.monotonic_time(:millisecond)
    bucket = rem(shard_id, max(state.max_concurrency, 1))
    slot = max(now, Map.get(state.identify_slots, bucket, now))
    slots = Map.put(state.identify_slots, bucket, slot + @identify_interval_ms)

    {:reply, slot - now, %{state | identify_slots: slots}}
  end

  def handle_call({:shard_for_guild, guild_id}, _from, state),
    do: {:reply, Sharding.shard_for(guild_id, state.shard_count), state}

  def handle_call(:shard_count, _from, state), do: {:reply, state.shard_count, state}

  def handle_call({:shard_status, shard_id}, _from, state) do
    status = if shard = state.shards[shard_id], do: Shard.status(shard), else: :dead
    {:reply, status, state}
  end

  def handle_call(:shard_statuses, _from, state) do
    statuses =
      state.shards
      |> Task.async_stream(fn {id, shard} -> {id, Shard.status(shard)} end,
        timeout: 6_000,
        ordered: false
      )
      |> Enum.reduce(%{}, fn
        {:ok, {id, status}}, acc -> Map.put(acc, id, status)
        _timed_out, acc -> acc
      end)

    {:reply, statuses, state}
  end

  def handle_call({:restart_shard, shard_id}, _from, state) do
    case state.shards[shard_id] do
      nil ->
        {:reply, {:error, :not_found}, state}

      old ->
        # demonitor the old shard so its :DOWN doesn't restart it a second time
        {refs, others} = Map.split_with(state.shard_refs, fn {_ref, id} -> id == shard_id end)
        Enum.each(refs, fn {ref, _id} -> Process.demonitor(ref, [:flush]) end)
        DynamicSupervisor.terminate_child(state.shard_supervisor, old)

        case Pool.start(%{Pool.forget(state, shard_id) | shard_refs: others}, shard_id) do
          {:ok, state} ->
            {:reply, :ok, state}

          {:error, reason} ->
            {:reply, {:error, reason}, %{Pool.forget(state, shard_id) | shard_refs: others}}
        end
    end
  end
end
