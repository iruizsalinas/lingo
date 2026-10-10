defmodule Lingo.Cache.Tables do
  @moduledoc false
  use GenServer

  alias Lingo.Cache.{Entries, Mutation, Policy, Storage}

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
              table: Storage.table(policy, true),
              policy: policy
            }

        {resource, Map.put(state, :revision, 0)}
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
    do:
      {:reply, true, Map.update!(states, name, &Mutation.apply(&1, name, [{:put, entry, kept?}]))}

  def handle_call({:delete, name, key}, _, states),
    do: {:reply, true, Map.update!(states, name, &Mutation.apply(&1, name, [{:delete, key}]))}

  def handle_call({:clear, name}, _, states),
    do: {:reply, true, Map.update!(states, name, &Mutation.apply(&1, name, [:clear]))}

  def handle_call({:stats, name}, _, states),
    do: {:reply, Lingo.Cache.Statistics.entries(states[name]), states}

  def handle_call({:select_delete, name, spec}, _, states) do
    state = states[name]

    {count, state} = Mutation.delete_selected(state, spec)
    {:reply, count, Map.put(states, name, state)}
  end

  def handle_call({:snapshot, names}, _, states) do
    versions = Map.new(names, fn name -> {name, {states[name].table, states[name].revision}} end)
    {:reply, versions, states}
  end

  def handle_call({:rest, versions, operations}, _, states) do
    states =
      Enum.reduce(operations, states, fn {name, actions}, states ->
        state = states[name]

        if state && versions[name] == {state.table, state.revision},
          do: Map.put(states, name, Mutation.apply(state, name, actions)),
          else: states
      end)

    {:reply, :ok, states}
  end

  @impl true
  def handle_info(:sweep, states) do
    states =
      Map.new(states, fn
        {name, %{meta: _} = state} -> {name, Mutation.sweep(state)}
        pair -> pair
      end)

    Process.send_after(self(), :sweep, 1_000)
    {:noreply, states}
  end
end
