defmodule Lingo.Gateway.ShardManager do
  @moduledoc false

  # Starts a bot's shards on this node, restarts dead ones, routes payloads
  # to the right shard (on whichever connected node runs it), and once every
  # shard here is up registers commands and answers await_ready/1. Resharding
  # is in Reshard; each generation of shards is a Pool.

  # time for every shard to close before the session store saves
  use GenServer, shutdown: 30_000

  alias Lingo.Gateway.{Connection, Groups, Intents, Sessions, Shard, Sharding}
  alias Lingo.Gateway.ShardManager.{Pool, Reshard}
  alias Lingo.Instance

  defstruct [
    :bot,
    :token,
    :intents,
    :shard_supervisor,
    :gateway_url,
    :auto_reshard,
    :reshard_started,
    :reshard_timer,
    :next,
    configured_count: :auto,
    configured_ids: :all,
    encoding: :json,
    compression: :zlib,
    presence: [],
    current: %Pool{},
    ready: false,
    ready_waiters: []
  ]

  def start_link(opts) do
    bot = Keyword.fetch!(opts, :bot)
    GenServer.start_link(__MODULE__, opts, name: Instance.process_name(bot, __MODULE__))
  end

  defp server, do: Instance.process_name(__MODULE__)

  # broadcasts and presence reach every node's shards
  def broadcast(payload), do: cluster_cast({:broadcast, payload})
  def update_presence(presence), do: cluster_cast({:update_presence, presence})

  def send_to_guild_shard(guild_id, payload),
    do: GenServer.cast(server(), {:send_to_guild_shard, guild_id, payload})

  def shard_ready(shard_id, count), do: GenServer.cast(server(), {:shard_ready, shard_id, count})

  # Discord's plan is fetched here, in the caller, so the manager never
  # waits on HTTP; the manager checks again when it gets it
  def reshard do
    with :ok <- GenServer.call(server(), :reshard_allowed),
         {:ok, plan} <- Sharding.fetch() do
      GenServer.call(server(), {:reshard, plan})
    end
  end

  def shard_for_guild(guild_id), do: GenServer.call(server(), {:shard_for_guild, guild_id})
  def shard_count, do: GenServer.call(server(), :shard_count)
  def shard_status(shard_id), do: GenServer.call(server(), {:shard_status, shard_id})
  def shard_statuses, do: GenServer.call(server(), :shard_statuses)
  def restart_shard(shard_id), do: GenServer.call(server(), {:restart_shard, shard_id}, 30_000)

  # the flag answers without a call once ready, even with a timeout of 0
  def await_ready(timeout) do
    if Instance.get(:gateway_ready, false),
      do: :ok,
      else: GenServer.call(server(), :await_ready, timeout)
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
  end

  defp cluster_cast(message) do
    case Groups.managers(Instance.current()) do
      [] -> GenServer.cast(server(), message)
      managers -> Enum.each(managers, &GenServer.cast(&1, message))
    end
  end

  @impl true
  def init(opts) do
    # stops the shards in terminate/2, before the session store saves
    Process.flag(:trap_exit, true)
    bot = Keyword.fetch!(opts, :bot)
    Instance.put_current(bot)
    Instance.put(bot, :latency_table, :ets.new(:latency, [:public, :set]))
    Groups.join_manager(bot)

    {:ok, shard_supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)
    sharding = opts[:sharding] || []
    gateway = opts[:gateway] || []

    send(self(), :start_shards)

    {:ok,
     %__MODULE__{
       bot: bot,
       token: Keyword.fetch!(opts, :token),
       intents: Intents.resolve(opts[:intents] || [:guilds, :guild_messages]),
       shard_supervisor: shard_supervisor,
       configured_count: Keyword.get(sharding, :count, :auto),
       configured_ids: Keyword.get(sharding, :ids, :all),
       auto_reshard: sharding[:auto_reshard] || nil,
       encoding: Keyword.get(gateway, :encoding, :json),
       compression: Keyword.get(gateway, :compression, :zlib),
       presence: opts[:presence] || []
     }}
  end

  @impl true
  def terminate(_reason, state) do
    DynamicSupervisor.stop(state.shard_supervisor, :shutdown)
  catch
    :exit, _already_stopped -> :ok
  end

  @impl true
  def handle_info(:start_shards, state) do
    case Sharding.fetch() do
      {:ok, plan} ->
        count = Sharding.count(state.configured_count, plan.recommended)
        Instance.put(state.bot, :shard_count, count)
        state = %{state | gateway_url: plan.url}
        ids = Sharding.ids(state.configured_ids, count)
        Reshard.schedule(state)
        {:noreply, %{state | current: Pool.start_all(%Pool{count: count}, ids, state)}}

      {:error, _reason} ->
        Process.send_after(self(), :start_shards, 5_000)
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {state, count, shard_id} = pop_ref(state, ref)
    if shard_id, do: Process.send_after(self(), {:restart_dead_shard, count, shard_id}, 5_000)
    {:noreply, state}
  end

  def handle_info({:restart_dead_shard, count, shard_id}, state) do
    with {key, pool} <- pool(state, count),
         false <- Map.has_key?(pool.shards, shard_id) do
      case Pool.start(pool, shard_id, state) do
        {:ok, pool} ->
          {:noreply, Map.put(state, key, pool)}

        {:error, _reason} ->
          Process.send_after(self(), {:restart_dead_shard, count, shard_id}, 10_000)
          {:noreply, state}
      end
    else
      _gone_or_running -> {:noreply, state}
    end
  end

  def handle_info(:check_reshard, state), do: {:noreply, Reshard.check(state)}
  def handle_info({:reshard_timeout, count}, state), do: {:noreply, Reshard.abort(state, count)}

  def handle_info({:EXIT, pid, reason}, %{shard_supervisor: pid} = state),
    do: {:stop, reason, state}

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def handle_cast({:broadcast, payload}, state) do
    Enum.each(state.current.shards, fn {_id, shard} -> Shard.send_payload(shard, payload) end)
    {:noreply, state}
  end

  # the shard may run on another node
  def handle_cast({:send_to_guild_shard, guild_id, payload}, %{current: pool} = state) do
    shard_id = Sharding.shard_for(guild_id, pool.count)

    cond do
      shard = pool.shards[shard_id] -> Shard.send_payload(shard, payload)
      pid = Groups.shard(state.bot, shard_id, pool.count) -> Connection.send_payload(pid, payload)
      true -> :ok
    end

    {:noreply, state}
  end

  # shards started later identify with the latest presence
  def handle_cast({:update_presence, presence}, state) do
    for pool <- [state.current, state.next],
        pool != nil,
        {_id, shard} <- pool.shards,
        pid = Shard.connection(shard),
        do: Connection.update_presence(pid, presence)

    {:noreply, %{state | presence: presence}}
  end

  def handle_cast({:shard_ready, shard_id, count}, state) do
    case pool(state, count) do
      {:current, pool} ->
        {:noreply, maybe_fire_ready(%{state | current: Pool.ready(pool, shard_id)})}

      {:next, pool} ->
        {:noreply, maybe_switch(%{state | next: Pool.ready(pool, shard_id)})}

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:shard_for_guild, guild_id}, _from, state),
    do: {:reply, Sharding.shard_for(guild_id, state.current.count), state}

  def handle_call(:shard_count, _from, state), do: {:reply, state.current.count, state}

  def handle_call(:reshard_allowed, _from, state) do
    case Reshard.blocked(state) do
      nil -> {:reply, :ok, state}
      reason -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:reshard, plan}, _from, state) do
    {reply, state} = Reshard.request(state, plan)
    {:reply, reply, state}
  end

  def handle_call(:await_ready, _from, %{ready: true} = state), do: {:reply, :ok, state}

  def handle_call(:await_ready, from, state),
    do: {:noreply, %{state | ready_waiters: [from | state.ready_waiters]}}

  def handle_call({:shard_status, shard_id}, _from, state) do
    status = if shard = state.current.shards[shard_id], do: Shard.status(shard), else: :dead
    {:reply, status, state}
  end

  def handle_call(:shard_statuses, _from, state),
    do: {:reply, Pool.statuses(state.current), state}

  # from scratch: the shard identifies again
  def handle_call({:restart_shard, shard_id}, _from, %{current: pool} = state) do
    if Map.has_key?(pool.shards, shard_id) do
      Sessions.delete(state.bot, shard_id, pool.count)
      {reply, pool} = Pool.restart(pool, shard_id, state)
      {:reply, reply, %{state | current: pool}}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  # once, at startup: a reshard or a reconnecting shard doesn't count
  defp maybe_fire_ready(%{ready: false, current: pool} = state) do
    if Pool.all_ready?(pool) do
      Instance.put(state.bot, :gateway_ready, true)
      Lingo.Telemetry.execute([:gateway, :ready], %{}, %{shard_count: pool.count})
      Lingo.Bot.Sync.register_on_ready()
      Enum.each(state.ready_waiters, &GenServer.reply(&1, :ok))
      %{state | ready: true, ready_waiters: []}
    else
      state
    end
  end

  defp maybe_fire_ready(state), do: state

  defp maybe_switch(%{next: next} = state),
    do: if(Pool.all_ready?(next), do: Reshard.switch(state), else: state)

  # the generation with this shard count
  defp pool(%{current: %Pool{count: count} = pool}, count), do: {:current, pool}
  defp pool(%{next: %Pool{count: count} = pool}, count), do: {:next, pool}
  defp pool(_state, _count), do: nil

  defp pop_ref(state, ref) do
    Enum.find_value([:current, :next], {state, nil, nil}, fn key ->
      with %Pool{} = pool <- Map.get(state, key),
           {shard_id, pool} when shard_id != nil <- Pool.pop_ref(pool, ref) do
        {Map.put(state, key, pool), pool.count, shard_id}
      else
        _ -> nil
      end
    end)
  end
end
