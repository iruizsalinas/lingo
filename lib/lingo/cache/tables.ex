defmodule Lingo.Cache.Tables do
  @moduledoc false

  # Owns a bot's cache tables: unnamed public ETS tables, one per resource,
  # whose ids live in the bot's config.

  use GenServer

  @resources [:guilds, :channels, :users, :members, :presences, :roles, :voice_states, :messages]
  @defaults [max_messages_per_channel: 200, enabled: @resources]

  def start_link(opts) do
    bot = Keyword.fetch!(opts, :bot)
    GenServer.start_link(__MODULE__, opts, name: Lingo.Instance.process_name(bot, __MODULE__))
  end

  @impl true
  def init(opts) do
    bot = Keyword.fetch!(opts, :bot)
    Lingo.Instance.put_current(bot)

    config =
      case Keyword.get(opts, :config) do
        false -> [enabled: []]
        nil -> []
        config -> config
      end

    config = Keyword.merge(@defaults, config)

    tables =
      for resource <- List.wrap(config[:enabled]), resource in @resources, into: %{} do
        type = if resource == :messages, do: :ordered_set, else: :set
        {resource, :ets.new(resource, [type, :public, {:read_concurrency, true}])}
      end

    Lingo.Instance.put(bot, :cache, %{
      tables: tables,
      max_messages: config[:max_messages_per_channel]
    })

    {:ok, bot}
  end

  @doc "The current bot's table for a resource, or nil when it isn't cached."
  @spec table(atom()) :: :ets.tid() | nil
  def table(resource) do
    case Lingo.Instance.get(:cache) do
      %{tables: %{^resource => table}} -> table
      _ -> nil
    end
  end

  @spec max_messages() :: non_neg_integer()
  def max_messages, do: Lingo.Instance.get(:cache).max_messages

  @spec get(atom(), term()) :: term()
  def get(resource, key) do
    with table when table != nil <- table(resource),
         [{^key, value}] <- :ets.lookup(table, key) do
      value
    else
      _ -> nil
    end
  end

  @spec insert(atom(), tuple()) :: true | :ok
  def insert(resource, entry) do
    if table = table(resource), do: :ets.insert(table, entry), else: :ok
  end

  @spec delete(atom(), term()) :: true | :ok
  def delete(resource, key) do
    if table = table(resource), do: :ets.delete(table, key), else: :ok
  end

  @spec select(atom(), :ets.match_spec()) :: [term()]
  def select(resource, spec) do
    if table = table(resource), do: :ets.select(table, spec), else: []
  end

  @spec select_delete(atom(), :ets.match_spec()) :: non_neg_integer()
  def select_delete(resource, spec) do
    if table = table(resource), do: :ets.select_delete(table, spec), else: 0
  end
end
