defmodule Lingo.Gateway.ShardManager do
  @moduledoc false

  use GenServer

  import Bitwise

  alias Lingo.Gateway.{Intents, Shard}

  defstruct [
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
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def broadcast(payload) do
    GenServer.cast(__MODULE__, {:broadcast, payload})
  end

  def send_to_shard(shard_id, payload) do
    GenServer.cast(__MODULE__, {:send_to_shard, shard_id, payload})
  end

  def send_to_guild_shard(guild_id, payload) do
    GenServer.cast(__MODULE__, {:send_to_guild_shard, guild_id, payload})
  end

  def shard_for_guild(guild_id) do
    GenServer.call(__MODULE__, {:shard_for_guild, guild_id})
  end

  def shard_count do
    GenServer.call(__MODULE__, :shard_count)
  end

  def shard_status(shard_id) do
    GenServer.call(__MODULE__, {:shard_status, shard_id})
  end

  def shard_statuses do
    GenServer.call(__MODULE__, :shard_statuses)
  end

  def restart_shard(shard_id) do
    GenServer.call(__MODULE__, {:restart_shard, shard_id}, 30_000)
  end

  def reshard do
    GenServer.cast(__MODULE__, :reshard)
  end

  def shard_ready(shard_id) do
    GenServer.cast(__MODULE__, {:shard_ready, shard_id})
  end

  def update_presence(presence) do
    GenServer.cast(__MODULE__, {:update_presence, presence})
  end

  # Reserves the next identify slot for this shard's rate limit bucket and
  # returns how long to wait, in ms, before sending Identify.
  def reserve_identify(shard_id) do
    GenServer.call(__MODULE__, {:reserve_identify, shard_id}, 10_000)
  catch
    :exit, _ -> 0
  end

  @impl true
  def init(opts) do
    token = Keyword.fetch!(opts, :token)
    intents = Keyword.fetch!(opts, :intents) |> Intents.resolve()
    sharding = Keyword.get(opts, :sharding, [])
    presence = Keyword.get(opts, :presence, [])

    {:ok, shard_sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

    state = %__MODULE__{
      token: token,
      intents: intents,
      shard_supervisor: shard_sup,
      configured_count: Keyword.get(sharding, :count, :auto),
      configured_ids: Keyword.get(sharding, :ids, :all),
      presence: presence
    }

    send(self(), :start_shards)
    {:ok, state}
  end

  @impl true
  def handle_info(:start_shards, state) do
    case fetch_gateway_bot(state.token) do
      {:ok, url, shard_count, max_concurrency, remaining, reset_after} ->
        if remaining < shard_count do
          Process.send_after(self(), :start_shards, reset_after + 1_000)
          {:noreply, state}
        else
          count = resolve_count(state.configured_count, shard_count)
          ids = resolve_ids(state.configured_ids, count)
          state = %{state | gateway_url: url, max_concurrency: max_concurrency}
          state = start_shards(state, count, ids)
          {:noreply, %{state | shard_count: count, expected_shard_count: length(ids)}}
        end

      {:error, _reason} ->
        Process.send_after(self(), :start_shards, 5_000)
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.get(state.shard_refs, ref) do
      nil ->
        {:noreply, state}

      shard_id ->
        state = %{
          state
          | shard_refs: Map.delete(state.shard_refs, ref),
            shards: Map.delete(state.shards, shard_id),
            ready_shards: Map.delete(state.ready_shards, shard_id)
        }

        Process.send_after(self(), {:restart_dead_shard, shard_id}, 5_000)
        {:noreply, state}
    end
  end

  def handle_info({:restart_dead_shard, shard_id}, state) do
    if not Map.has_key?(state.shards, shard_id) do
      opts = [
        shard_id: shard_id,
        shard_count: state.shard_count,
        token: state.token,
        intents: state.intents,
        gateway_url: state.gateway_url,
        presence: state.presence,
        shard_manager: self()
      ]

      case DynamicSupervisor.start_child(state.shard_supervisor, {Shard, opts}) do
        {:ok, pid} ->
          ref = Process.monitor(pid)

          {:noreply,
           %{
             state
             | shards: Map.put(state.shards, shard_id, pid),
               shard_refs: Map.put(state.shard_refs, ref, shard_id)
           }}

        {:error, _} ->
          Process.send_after(self(), {:restart_dead_shard, shard_id}, 10_000)
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast({:broadcast, payload}, state) do
    each_connection(state, fn conn_pid ->
      Lingo.Gateway.Connection.send_payload(conn_pid, payload)
    end)

    {:noreply, state}
  end

  def handle_cast({:send_to_shard, shard_id, payload}, state) do
    case Map.get(state.shards, shard_id) do
      nil -> :ok
      shard_sup -> send_to_connection(shard_sup, payload)
    end

    {:noreply, state}
  end

  def handle_cast({:send_to_guild_shard, guild_id, payload}, state) do
    shard_id = compute_shard(guild_id, state.shard_count)

    case Map.get(state.shards, shard_id) do
      nil -> :ok
      shard_sup -> send_to_connection(shard_sup, payload)
    end

    {:noreply, state}
  end

  def handle_cast({:update_presence, presence}, state) do
    each_connection(state, fn conn_pid ->
      Lingo.Gateway.Connection.update_presence(conn_pid, presence)
    end)

    # shards started later identify with the latest presence
    {:noreply, %{state | presence: presence}}
  end

  def handle_cast({:shard_ready, shard_id}, state) do
    ready_shards = Map.put(state.ready_shards, shard_id, true)
    state = %{state | ready_shards: ready_shards}

    state =
      if not state.ready_fired and map_size(ready_shards) == state.expected_shard_count do
        Lingo.Gateway.Dispatcher.dispatch(:ready, %{shard_count: state.shard_count})
        %{state | ready_fired: true}
      else
        state
      end

    {:noreply, state}
  end

  def handle_cast(:reshard, %{configured_count: n} = state) when is_integer(n) do
    {:noreply, state}
  end

  def handle_cast(:reshard, state) do
    old_shards = state.shards

    case fetch_gateway_bot(state.token) do
      {:ok, url, new_count, max_concurrency, remaining, _reset_after} ->
        if remaining >= new_count do
          ids = resolve_ids(state.configured_ids, new_count)

          new_state = %{
            state
            | shard_count: new_count,
              gateway_url: url,
              shards: %{},
              shard_refs: %{},
              ready_shards: %{},
              ready_fired: false,
              expected_shard_count: length(ids),
              max_concurrency: max_concurrency
          }

          new_state = start_shards(new_state, new_count, ids)

          Enum.each(old_shards, fn {_id, old_pid} ->
            DynamicSupervisor.terminate_child(state.shard_supervisor, old_pid)
          end)

          {:noreply, new_state}
        else
          {:noreply, state}
        end

      {:error, _} ->
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

  def handle_call({:shard_for_guild, guild_id}, _from, state) do
    {:reply, compute_shard(guild_id, state.shard_count), state}
  end

  def handle_call(:shard_count, _from, state) do
    {:reply, state.shard_count, state}
  end

  def handle_call({:shard_status, shard_id}, _from, state) do
    status =
      case Map.get(state.shards, shard_id) do
        nil -> :dead
        shard_sup -> find_connection_status(shard_sup)
      end

    {:reply, status, state}
  end

  def handle_call(:shard_statuses, _from, state) do
    statuses =
      state.shards
      |> Task.async_stream(
        fn {id, shard_sup} -> {id, find_connection_status(shard_sup)} end,
        timeout: 6_000,
        ordered: false
      )
      |> Enum.reduce(%{}, fn
        {:ok, {id, status}}, acc -> Map.put(acc, id, status)
        _, acc -> acc
      end)

    {:reply, statuses, state}
  end

  def handle_call({:restart_shard, shard_id}, _from, state) do
    case Map.get(state.shards, shard_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      old_pid ->
        # demonitor old shard so :DOWN doesn't trigger a duplicate restart
        {old_ref, remaining_refs} =
          Enum.reduce(state.shard_refs, {nil, %{}}, fn {ref, sid}, {found, acc} ->
            if sid == shard_id, do: {ref, acc}, else: {found, Map.put(acc, ref, sid)}
          end)

        if old_ref, do: Process.demonitor(old_ref, [:flush])

        DynamicSupervisor.terminate_child(state.shard_supervisor, old_pid)

        opts = [
          shard_id: shard_id,
          shard_count: state.shard_count,
          token: state.token,
          intents: state.intents,
          gateway_url: state.gateway_url,
          presence: state.presence,
          shard_manager: self()
        ]

        case DynamicSupervisor.start_child(state.shard_supervisor, {Shard, opts}) do
          {:ok, pid} ->
            new_ref = Process.monitor(pid)

            {:reply, :ok,
             %{
               state
               | shards: Map.put(state.shards, shard_id, pid),
                 shard_refs: Map.put(remaining_refs, new_ref, shard_id)
             }}

          {:error, reason} ->
            {:reply, {:error, reason},
             %{state | shards: Map.delete(state.shards, shard_id), shard_refs: remaining_refs}}
        end
    end
  end

  defp compute_shard(_guild_id, 0), do: 0

  defp compute_shard(guild_id, shard_count) when is_binary(guild_id) do
    rem(String.to_integer(guild_id) >>> 22, shard_count)
  end

  defp each_connection(state, fun) do
    Enum.each(state.shards, fn {_id, shard_sup} ->
      case find_connection(shard_sup) do
        nil -> :ok
        conn_pid -> fun.(conn_pid)
      end
    end)
  end

  defp send_to_connection(shard_sup, payload) do
    case find_connection(shard_sup) do
      nil -> :ok
      conn_pid -> Lingo.Gateway.Connection.send_payload(conn_pid, payload)
    end
  end

  defp find_connection_status(shard_sup) do
    case find_connection(shard_sup) do
      nil -> :dead
      pid -> Lingo.Gateway.Connection.status(pid)
    end
  end

  defp find_connection(shard_sup) do
    if Process.alive?(shard_sup) do
      shard_sup
      |> Supervisor.which_children()
      |> Enum.find_value(fn
        {_, pid, :worker, [Lingo.Gateway.Connection]} when is_pid(pid) -> pid
        _ -> nil
      end)
    end
  rescue
    _ -> nil
  end

  defp fetch_gateway_bot(token) do
    headers = [
      {"authorization", "Bot #{token}"},
      {"user-agent",
       "DiscordBot (https://github.com/iruizsalinas/lingo, #{Mix.Project.config()[:version]})"}
    ]

    with {:ok, %{status: 200, body: body}} <-
           Lingo.Api.HTTP.request(:get, "https://discord.com/api/v10/gateway/bot", headers),
         {:ok, body} <- JSON.decode(body) do
      url = body["url"] |> String.trim_trailing("/")
      shards = body["shards"]
      ssl = body["session_start_limit"] || %{}
      max_concurrency = ssl["max_concurrency"] || 1
      remaining = ssl["remaining"] || 1000
      reset_after = ssl["reset_after"] || 0
      {:ok, url, shards, max_concurrency, remaining, reset_after}
    else
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Identify pacing is enforced per bucket by reserve_identify/1, so shards can
  # all be started right away without blocking this process.
  defp start_shards(state, shard_count, shard_ids) do
    manager_pid = self()

    {shards, refs} =
      Enum.reduce(shard_ids, {%{}, %{}}, fn shard_id, {shard_acc, ref_acc} ->
        opts = [
          shard_id: shard_id,
          shard_count: shard_count,
          token: state.token,
          intents: state.intents,
          gateway_url: state.gateway_url,
          presence: state.presence,
          shard_manager: manager_pid
        ]

        case DynamicSupervisor.start_child(state.shard_supervisor, {Shard, opts}) do
          {:ok, pid} ->
            ref = Process.monitor(pid)
            {Map.put(shard_acc, shard_id, pid), Map.put(ref_acc, ref, shard_id)}

          {:error, _} ->
            {shard_acc, ref_acc}
        end
      end)

    %{state | shards: shards, shard_refs: refs}
  end

  defp resolve_count(:auto, discord_count), do: discord_count
  defp resolve_count(n, _discord_count) when is_integer(n), do: n

  defp resolve_ids(:all, count), do: Enum.to_list(0..(count - 1))
  defp resolve_ids(ids, _count) when is_list(ids), do: ids
end
