defmodule Lingo.Bot.Cooldowns do
  @moduledoc false

  # Command cooldowns: at most `uses` per `per` ms for each key, as a sliding
  # window of use times. One process per bot serializes the check-and-count,
  # and forgets keys whose window has passed.

  use GenServer

  alias Lingo.Instance

  @sweep_ms 60_000

  def start_link(opts) do
    bot = Keyword.fetch!(opts, :bot)
    GenServer.start_link(__MODULE__, :ok, name: Instance.process_name(bot, __MODULE__))
  end

  @doc "Counts a use of `key`, or says how long until one is allowed."
  @spec hit(term(), term(), {pos_integer(), pos_integer(), atom()}) ::
          :ok | {:wait, pos_integer()}
  def hit(bot, key, {uses, per, _scope}) do
    GenServer.call(Instance.process_name(bot, __MODULE__), {:hit, key, uses, per})
  catch
    # without the process (tests that don't start it), nothing is limited
    :exit, {:noproc, _} -> :ok
  end

  @impl true
  def init(:ok) do
    Process.send_after(self(), :sweep, @sweep_ms)
    {:ok, %{}}
  end

  @impl true
  def handle_call({:hit, key, uses, per}, _from, state) do
    now = System.monotonic_time(:millisecond)
    {_per, times} = Map.get(state, key, {per, []})
    times = Enum.filter(times, &(&1 > now - per))

    if length(times) < uses do
      {:reply, :ok, Map.put(state, key, {per, [now | times]})}
    else
      oldest = List.last(times)
      {:reply, {:wait, max(oldest + per - now, 1)}, Map.put(state, key, {per, times})}
    end
  end

  @impl true
  def handle_info(:sweep, state) do
    Process.send_after(self(), :sweep, @sweep_ms)
    now = System.monotonic_time(:millisecond)

    {:noreply,
     Map.filter(state, fn {_key, {per, times}} -> Enum.any?(times, &(&1 > now - per)) end)}
  end
end
