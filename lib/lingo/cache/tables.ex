defmodule Lingo.Cache.Tables do
  @moduledoc false
  use GenServer

  alias Lingo.Cache.{Entries, Policy}

  def start_link(opts) do
    bot = Keyword.fetch!(opts, :bot)
    GenServer.start_link(__MODULE__, opts, name: Lingo.Instance.process_name(bot, __MODULE__))
  end

  @impl true
  def init(opts) do
    bot = Keyword.fetch!(opts, :bot)
    Lingo.Instance.put_current(bot)
    policies = Policy.normalize(opts[:config])

    resources =
      Map.new(policies, fn {resource, policy} ->
        state =
          if Policy.managed?(policy),
            do: Entries.new(policy),
            else: %{
              table: :ets.new(resource, [:set, :public, read_concurrency: true]),
              policy: policy
            }

        {resource, state}
      end)

    # One current-user record is bot identity, independent of optional resource caches.
    identity = :ets.new(:identity, [:set, :public, read_concurrency: true])
    Lingo.Instance.put(bot, :cache, %{resources: resources, identity: identity})
    ttl? = Enum.any?(policies, fn {_, policy} -> policy.ttl != :infinity end)
    if ttl?, do: Process.send_after(self(), :sweep, 1_000)
    {:ok, resources}
  end

  defdelegate resource(name), to: Lingo.Cache.Access
  defdelegate table(name), to: Lingo.Cache.Access
  defdelegate enabled?(names), to: Lingo.Cache.Access
  defdelegate wants?(name, id), to: Lingo.Cache.Access
  defdelegate get(name, key), to: Lingo.Cache.Access
  defdelegate insert(name, entry), to: Lingo.Cache.Access
  defdelegate delete(name, key), to: Lingo.Cache.Access
  defdelegate select(name, spec), to: Lingo.Cache.Access
  defdelegate select_delete(name, spec), to: Lingo.Cache.Access
  defdelegate clear(name), to: Lingo.Cache.Access
  defdelegate stats(), to: Lingo.Cache.Statistics
  defdelegate current_user(), to: Lingo.Cache.Identity
  defdelegate put_current_user(user), to: Lingo.Cache.Identity

  @impl true
  def handle_call({:put, name, entry, kept?}, _, states),
    do: {:reply, true, Map.update!(states, name, &Entries.put(&1, name, entry, kept?))}

  def handle_call({:delete, name, key}, _, states),
    do: {:reply, true, Map.update!(states, name, &Entries.delete(&1, key))}

  def handle_call({:clear, name}, _, states),
    do: {:reply, true, Map.update!(states, name, &Entries.clear/1)}

  def handle_call({:stats, name}, _, states),
    do: {:reply, Lingo.Cache.Statistics.entries(states[name]), states}

  def handle_call({:select_delete, name, spec}, _, states) do
    state = states[name]

    keys =
      :ets.select(
        state.table,
        Enum.map(spec, fn {head, guards, _} -> {head, guards, [{:element, 1, :"$_"}]} end)
      )

    state = Enum.reduce(keys, state, &Entries.delete(&2, &1))
    {:reply, length(keys), Map.put(states, name, state)}
  end

  @impl true
  def handle_info(:sweep, states) do
    states =
      Map.new(states, fn
        {name, %{meta: _} = state} -> {name, Entries.sweep(state)}
        pair -> pair
      end)

    Process.send_after(self(), :sweep, 1_000)
    {:noreply, states}
  end
end
