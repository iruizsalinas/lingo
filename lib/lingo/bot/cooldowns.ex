defmodule Lingo.Bot.Cooldowns do
  @moduledoc false

  # Command cooldowns: at most `uses` per `per` ms for each key, in a window
  # that starts at the first use. Counts live in a public ETS table, so
  # commands count without a process in the way; the process owns the table
  # and forgets windows that have passed. Two uses resetting an expired
  # window at the same moment may let one extra use through.

  use GenServer

  alias Lingo.Instance

  @sweep_ms 60_000
  @scopes [:user, :member, :guild, :channel, :global]

  @type cooldown :: {pos_integer(), pos_integer(), atom()}

  ## The :cooldown option

  @doc """
  Validates a `:cooldown` at compile time: `{uses, per_ms}`,
  `{uses, per_ms, scope}`, `[uses:, per:, scope:]`, or a function capture
  returning one of those (or nil) for each use.
  """
  def validate!(nil), do: nil

  def validate!(fun) when is_function(fun) do
    if external_fun?(fun),
      do: {:dynamic, fun},
      else: raise(ArgumentError, "a :cooldown function must be a capture like &Mod.fun/1")
  end

  def validate!(spec) do
    case normalize(spec) do
      {:ok, cooldown} -> cooldown
      :error -> raise ArgumentError, invalid(spec)
    end
  end

  @doc "The cooldown that applies to this use, or nil."
  @spec resolve(cooldown() | {:dynamic, function()} | nil, Lingo.Context.t()) :: cooldown() | nil
  def resolve({:dynamic, fun}, ctx) do
    case fun.(ctx) do
      nil ->
        nil

      spec ->
        case normalize(spec) do
          {:ok, cooldown} -> cooldown
          :error -> raise ArgumentError, "#{inspect(fun)} returned an " <> invalid(spec)
        end
    end
  end

  def resolve(cooldown, _ctx), do: cooldown

  @doc false
  def external_fun?(fun),
    do: is_function(fun, 1) and Function.info(fun, :type) == {:type, :external}

  defp normalize({uses, per}), do: normalize({uses, per, :user})

  defp normalize({uses, per, scope} = cooldown)
       when is_integer(uses) and uses > 0 and is_integer(per) and per > 0 and scope in @scopes,
       do: {:ok, cooldown}

  defp normalize([{_, _} | _] = spec) do
    if Keyword.keyword?(spec) and Keyword.keys(spec) -- [:uses, :per, :scope] == [],
      do: normalize({spec[:uses], spec[:per], Keyword.get(spec, :scope, :user)}),
      else: :error
  end

  defp normalize(_spec), do: :error

  defp invalid(spec),
    do:
      "invalid :cooldown #{inspect(spec)}: use {uses, per_ms}, {uses, per_ms, scope} or " <>
        "[uses: n, per: ms, scope: s], with scope one of #{inspect(@scopes)}"

  ## Counting

  def start_link(opts) do
    bot = Keyword.fetch!(opts, :bot)
    GenServer.start_link(__MODULE__, bot, name: Instance.process_name(bot, __MODULE__))
  end

  @doc "Counts a use of `key`, or says how long until one is allowed."
  @spec hit(term(), term(), cooldown()) :: :ok | {:wait, pos_integer()}
  def hit(bot, key, {uses, per, _scope}) do
    table = Instance.process_name(bot, __MODULE__)
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(table, key) do
      [] ->
        # another use may have opened the window just now
        if :ets.insert_new(table, {key, 1, now, per}), do: :ok, else: count(table, key, uses, now)

      [{^key, _count, start, ^per}] when now - start >= per ->
        :ets.insert(table, {key, 1, now, per})
        :ok

      [_window] ->
        count(table, key, uses, now)
    end
  rescue
    # without the table (tests that don't start it), nothing is limited
    ArgumentError -> :ok
  end

  defp count(table, key, uses, now) do
    case :ets.lookup(table, key) do
      [{^key, _count, start, per}] ->
        if :ets.update_counter(table, key, {2, 1}) <= uses,
          do: :ok,
          else: {:wait, max(start + per - now, 1)}

      # swept in between: the window is over
      [] ->
        :ok
    end
  end

  @impl true
  def init(bot) do
    :ets.new(Instance.process_name(bot, __MODULE__), [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    Process.send_after(self(), :sweep, @sweep_ms)
    {:ok, Instance.process_name(bot, __MODULE__)}
  end

  @impl true
  def handle_info(:sweep, table) do
    Process.send_after(self(), :sweep, @sweep_ms)
    now = System.monotonic_time(:millisecond)
    # windows that started at least `per` ago
    :ets.select_delete(table, [
      {{:_, :_, :"$1", :"$2"}, [{:"=<", {:+, :"$1", :"$2"}, now}], [true]}
    ])

    {:noreply, table}
  end
end
