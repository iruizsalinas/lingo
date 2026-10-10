defmodule Lingo.Gateway.Identify do
  @moduledoc false

  # Decides when each shard may identify. Discord allows max_concurrency
  # identifies per 5 seconds, one per rate limit bucket (shard_id rem
  # max_concurrency), and a daily budget of them; going over the budget
  # resets the bot's token and drops every session.
  #
  # Every node running the bot has one of these; the first registers itself
  # globally, under the bot's name and token, and the others forward to it,
  # so shards spread across connected nodes share the limits. When the
  # leader goes away another takes over, first waiting out one interval in
  # case the old leader had just handed out slots.

  use GenServer

  require Logger

  alias Lingo.Gateway.Sharding
  alias Lingo.{Instance, Telemetry}

  @interval_ms 5_500
  @retry_ms 5_000

  defstruct [
    :bot,
    :name,
    :leader,
    :max_concurrency,
    :remaining,
    :reset_at,
    :paused_until,
    role: :follower,
    slots: %{}
  ]

  def start_link(opts) do
    bot = Keyword.fetch!(opts, :bot)
    GenServer.start_link(__MODULE__, opts, name: Instance.process_name(bot, __MODULE__))
  end

  @doc """
  Reserves an identify for a shard. `{:ok, delay}`: identify after `delay`
  ms. `{:wait, ms}`: no identify is available now, ask again after `ms`.
  """
  @spec reserve(non_neg_integer()) :: {:ok, non_neg_integer()} | {:wait, pos_integer()}
  def reserve(shard_id) do
    GenServer.call(Instance.process_name(__MODULE__), {:reserve, shard_id}, 15_000)
  catch
    :exit, _ -> {:wait, @retry_ms}
  end

  @impl true
  def init(opts) do
    bot = Keyword.fetch!(opts, :bot)
    Instance.put_current(bot)
    token_hash = :erlang.phash2(Instance.get(bot, :token, nil))
    state = %__MODULE__{bot: bot, name: {__MODULE__, bot, token_hash}}

    state =
      case opts[:plan] do
        nil -> state
        plan -> apply_plan(state, plan, now())
      end

    {:ok, lead(state)}
  end

  @impl true
  def handle_call({:reserve, shard_id}, _from, %{role: :leader} = state) do
    state = fetch_plan(state, now())
    {reply, state} = reserve(state, shard_id, now())
    {:reply, reply, state}
  end

  def handle_call({:reserve, _shard_id} = request, _from, %{leader: leader} = state) do
    {:reply, GenServer.call(leader, request, 10_000), state}
  catch
    :exit, _ -> {:reply, {:wait, @retry_ms}, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, leader, _reason}, %{leader: leader} = state),
    do: {:noreply, lead(%{state | leader: nil, paused_until: now() + @interval_ms})}

  # two leaders met after a netsplit healed, and this one lost
  def handle_info({:global_name_conflict, _name}, state),
    do: {:noreply, lead(%{state | role: :follower, paused_until: now() + @interval_ms})}

  def handle_info(_message, state), do: {:noreply, state}

  defp lead(state) do
    case :global.register_name(state.name, self(), &:global.random_notify_name/3) do
      :yes ->
        %{state | role: :leader, leader: nil}

      :no ->
        case :global.whereis_name(state.name) do
          # the leader went away in between
          :undefined ->
            lead(state)

          pid ->
            Process.monitor(pid)
            %{state | role: :follower, leader: pid}
        end
    end
  end

  defp reserve(%{remaining: nil} = state, _shard_id, _now), do: {{:wait, @retry_ms}, state}

  defp reserve(%{remaining: remaining} = state, shard_id, now) when remaining <= 0 do
    wait = max(state.reset_at - now, @retry_ms)
    Logger.warning("Lingo shard #{shard_id} waits #{wait} ms for the daily identify limit")
    Telemetry.execute([:gateway, :identify_limited], %{wait: wait}, %{shard_id: shard_id})
    {{:wait, wait}, state}
  end

  defp reserve(state, shard_id, now) do
    bucket = rem(shard_id, state.max_concurrency)
    # monotonic time may be negative, so a missing pause is nil rather than 0
    slot = state.slots |> Map.get(bucket, now) |> max(now) |> max(state.paused_until || now)

    {{:ok, slot - now},
     %{
       state
       | remaining: state.remaining - 1,
         slots: Map.put(state.slots, bucket, slot + @interval_ms)
     }}
  end

  # asks Discord when the budget is unknown, or used up and due to reset
  defp fetch_plan(%{remaining: nil} = state, now), do: refresh(state, now)

  defp fetch_plan(%{remaining: remaining, reset_at: reset_at} = state, now)
       when remaining <= 0 and now >= reset_at,
       do: refresh(state, now)

  defp fetch_plan(state, _now), do: state

  defp refresh(state, now) do
    case Lingo.Rest.Client.with_max_wait(5_000, &Sharding.fetch/0) do
      {:ok, plan} -> apply_plan(state, plan, now)
      {:error, _reason} -> state
    end
  end

  defp apply_plan(state, plan, now),
    do: %{
      state
      | max_concurrency: max(plan.max_concurrency, 1),
        remaining: plan.remaining,
        reset_at: now + plan.reset_after
    }

  defp now, do: System.monotonic_time(:millisecond)
end
