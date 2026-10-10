defmodule Lingo.Instance do
  @moduledoc false

  # One running bot. Its config lives in :persistent_term under its name, and
  # every process Lingo starts for it has that name in its process dictionary,
  # so internal code (and handler code) can find "the current bot" without
  # threading it through every call. Tasks inherit it through $callers.
  # Elsewhere the only running bot is used; with several running, callers pick
  # one with Lingo.with_bot/2.

  use GenServer

  @current {Lingo, :current_bot}
  @running {Lingo, :running_bots}

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: process_name(name, __MODULE__))
  end

  @doc "Name of one of the bot's processes."
  @spec process_name(term(), module()) :: atom()
  def process_name(name, role), do: Module.concat(name, role)

  @spec process_name(module()) :: atom()
  def process_name(role), do: process_name(current(), role)

  ## Current bot

  @spec current() :: term()
  def current do
    case Process.get(@current) do
      nil -> from_callers(Process.get(:"$callers", [])) || default()
      name -> name
    end
  end

  # tasks started from a bot's process (Task.async in a handler, say) act for it too
  defp from_callers([]), do: nil

  defp from_callers([pid | rest]) do
    case Process.info(pid, {:dictionary, @current}) do
      {{:dictionary, @current}, name} when name != :undefined -> name
      _missing_or_dead -> from_callers(rest)
    end
  end

  @spec put_current(term()) :: term() | nil
  def put_current(name), do: Process.put(@current, name)

  @spec with_current(term(), (-> result)) :: result when result: any()
  def with_current(nil, fun), do: fun.()

  def with_current(name, fun) do
    previous = put_current(name)

    try do
      fun.()
    after
      if previous == nil, do: Process.delete(@current), else: put_current(previous)
    end
  end

  @spec running() :: [term()]
  def running, do: :persistent_term.get(@running, [])

  defp default do
    case running() do
      [name] ->
        name

      [] ->
        raise ArgumentError, "no Lingo bot is running"

      names ->
        raise ArgumentError,
              "several Lingo bots are running (#{Enum.map_join(names, ", ", &inspect/1)}), " <>
                "pick one with Lingo.with_bot/2 or Lingo.put_bot/1"
    end
  end

  ## Config

  @spec get(atom(), term()) :: term()
  def get(key, default \\ nil), do: get(current(), key, default)

  @spec get(term(), atom(), term()) :: term()
  def get(name, key, default) do
    case :persistent_term.get({Lingo, :bot, name}, nil) do
      nil -> default
      config -> Map.get(config, key, default)
    end
  end

  @spec put(term(), atom(), term()) :: :ok
  def put(name, key, value) do
    locked(fn ->
      config = :persistent_term.get({Lingo, :bot, name}, %{})

      unless Map.get(config, key) == value,
        do: :persistent_term.put({Lingo, :bot, name}, Map.put(config, key, value))
    end)

    :ok
  end

  @doc "The application id, from READY or fetched once when READY hasn't arrived yet."
  @spec application_id() :: {:ok, String.t()} | {:error, Lingo.Error.t()}
  def application_id do
    name = current()

    case get(name, :application_id, nil) do
      nil ->
        with {:ok, %{"id" => id}} <- Lingo.Api.Application.get_current() do
          put(name, :application_id, id)
          {:ok, id}
        end

      id ->
        {:ok, id}
    end
  end

  ## Server: owns the config for the bot's lifetime

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    name = Keyword.fetch!(opts, :name)
    put_current(name)
    if bot = opts[:bot], do: Code.ensure_loaded(bot)

    config = opts |> Keyword.delete(:name) |> Map.new() |> Map.put(:name, name)
    :persistent_term.put({Lingo, :bot, name}, config)
    update_running(&[name | List.delete(&1, name)])

    {:ok, name}
  end

  @impl true
  def terminate(_reason, name) do
    update_running(&List.delete(&1, name))
    :persistent_term.erase({Lingo, :bot, name})
  end

  defp update_running(fun), do: locked(fn -> :persistent_term.put(@running, fun.(running())) end)

  # shards and bots start concurrently, so read-modify-writes of the shared
  # terms are serialized (writes are rare: startup and READY)
  defp locked(fun), do: :global.trans({__MODULE__, self()}, fun, [node()])
end
