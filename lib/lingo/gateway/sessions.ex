defmodule Lingo.Gateway.Sessions do
  @moduledoc false

  # Owns the table of gateway sessions, one row per shard, so a shard (or the
  # shard manager) that restarts resumes instead of identifying again. Rows
  # are keyed by {shard_id, shard_count}: a session only resumes under the
  # shard count it was identified with.
  #
  # With a session store configured, sessions are loaded when the bot starts,
  # each shard's is saved when it starts or resumes and forgotten when it
  # can't be resumed, and every shard's is saved again when the bot stops,
  # with its last sequence number. Store calls run here, one at a time, never
  # in a connection. This process starts before the shard manager, so it
  # stops after every shard has closed.

  use GenServer

  require Logger

  alias Lingo.Instance

  def start_link(opts) do
    bot = Keyword.fetch!(opts, :bot)
    GenServer.start_link(__MODULE__, opts, name: name(bot))
  end

  @spec fetch(term(), non_neg_integer(), pos_integer()) ::
          {String.t(), String.t(), non_neg_integer()} | nil
  def fetch(bot, shard_id, count) do
    with table when table != nil <- table(bot),
         [{_key, session_id, url, seq}] <- :ets.lookup(table, {shard_id, count}) do
      {session_id, url, seq}
    else
      _none -> nil
    end
  end

  @doc "Records a new session (READY), and saves it to the store."
  @spec put(term(), non_neg_integer(), pos_integer(), String.t(), String.t(), non_neg_integer()) ::
          :ok
  def put(bot, shard_id, count, session_id, url, seq) do
    if table = table(bot), do: :ets.insert(table, {{shard_id, count}, session_id, url, seq})
    save(bot, shard_id, count)
  end

  @doc "Saves a shard's session to the store, as it is now (RESUMED)."
  @spec save(term(), non_neg_integer(), pos_integer()) :: :ok
  def save(bot, shard_id, count), do: GenServer.cast(name(bot), {:save, {shard_id, count}})

  @doc "Records the latest sequence number of a stored session."
  @spec seq(term(), non_neg_integer(), pos_integer(), non_neg_integer()) :: :ok
  def seq(bot, shard_id, count, seq) do
    if table = table(bot), do: :ets.update_element(table, {shard_id, count}, {4, seq})
    :ok
  end

  @doc "Forgets a session that can't be resumed, here and in the store."
  @spec delete(term(), non_neg_integer(), pos_integer()) :: :ok
  def delete(bot, shard_id, count) do
    if table = table(bot), do: :ets.delete(table, {shard_id, count})
    GenServer.cast(name(bot), {:delete, shard_id, count})
  end

  @spec list(term()) :: [Lingo.Gateway.SessionStore.session()]
  def list(bot) do
    case table(bot) do
      nil -> []
      table -> table |> :ets.tab2list() |> Enum.map(&to_session/1) |> Enum.sort_by(& &1.shard_id)
    end
  end

  defp name(bot), do: Instance.process_name(bot, __MODULE__)
  defp table(bot), do: Instance.get(bot, :sessions_table, nil)

  defp to_session({{shard_id, count}, session_id, url, seq}),
    do: %{
      shard_id: shard_id,
      shard_count: count,
      session_id: session_id,
      resume_gateway_url: url,
      seq: seq
    }

  @impl true
  def init(opts) do
    # so terminate/2 runs, and saves, when the bot stops
    Process.flag(:trap_exit, true)
    bot = Keyword.fetch!(opts, :bot)
    Instance.put_current(bot)

    table = :ets.new(__MODULE__, [:public, :set, write_concurrency: true])
    Instance.put(bot, :sessions_table, table)

    store = opts[:store]
    ids = Keyword.get(opts, :ids, :all)

    if store && opts[:cache?] do
      Logger.warning(
        "Lingo resumes #{inspect(bot)}'s saved gateway sessions with its cache on: " <>
          "resumed sessions don't resend the guilds, so the cache starts without them"
      )
    end

    loaded = call(store, :load, [bot])

    for session <- (is_list(loaded) && loaded) || [],
        valid?(session),
        ids == :all or session.shard_id in ids,
        do: insert(table, session)

    {:ok, %{bot: bot, store: store, table: table}}
  end

  @impl true
  def handle_cast(_request, %{store: nil} = state), do: {:noreply, state}

  def handle_cast({:save, key}, state) do
    case :ets.lookup(state.table, key) do
      [row] -> call(state.store, :save, [state.bot, to_session(row)])
      [] -> :ok
    end

    {:noreply, state}
  end

  def handle_cast({:delete, shard_id, count}, state) do
    call(state.store, :delete, [state.bot, shard_id, count])
    {:noreply, state}
  end

  # every live session, with its last sequence number; sessions under
  # another shard count can't resume anymore
  @impl true
  def terminate(_reason, %{store: nil}), do: :ok

  def terminate(_reason, %{bot: bot, store: store}) do
    count = Instance.get(bot, :shard_count, nil)

    for session <- list(bot) do
      if count == nil or session.shard_count == count,
        do: call(store, :save, [bot, session]),
        else: call(store, :delete, [bot, session.shard_id, session.shard_count])
    end

    :ok
  end

  defp call(nil, _fun, _args), do: nil

  defp call({module, opts}, fun, args) do
    apply(module, fun, args ++ [opts])
  rescue
    e ->
      Logger.error("Lingo's session store failed to #{fun}: #{Exception.message(e)}")
      nil
  end

  defp valid?(%{
         shard_id: id,
         shard_count: count,
         session_id: session,
         resume_gateway_url: url,
         seq: seq
       }),
       do:
         is_integer(id) and id >= 0 and is_integer(count) and count > id and is_binary(session) and
           is_binary(url) and is_integer(seq)

  defp valid?(_other), do: false

  defp insert(table, session) do
    :ets.insert(
      table,
      {{session.shard_id, session.shard_count}, session.session_id, session.resume_gateway_url,
       session.seq}
    )
  end
end
