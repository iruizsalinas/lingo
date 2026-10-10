defmodule Lingo.Gateway.Sessions do
  @moduledoc false

  # Owns the table of gateway sessions, one row per shard, so a shard (or the
  # shard manager) that restarts resumes instead of identifying again. Rows
  # are keyed by {shard_id, shard_count}: a session only resumes under the
  # shard count it was identified with.
  #
  # With a session store configured, sessions are loaded when the bot starts
  # and saved when it stops. This process starts before the shard manager, so
  # it stops after every shard has closed.

  use GenServer

  require Logger

  alias Lingo.Instance

  def start_link(opts) do
    bot = Keyword.fetch!(opts, :bot)
    GenServer.start_link(__MODULE__, opts, name: Instance.process_name(bot, __MODULE__))
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

  @spec put(term(), non_neg_integer(), pos_integer(), String.t(), String.t(), non_neg_integer()) ::
          :ok
  def put(bot, shard_id, count, session_id, url, seq) do
    if table = table(bot), do: :ets.insert(table, {{shard_id, count}, session_id, url, seq})
    :ok
  end

  @doc "Records the latest sequence number of a stored session."
  @spec seq(term(), non_neg_integer(), pos_integer(), non_neg_integer()) :: :ok
  def seq(bot, shard_id, count, seq) do
    if table = table(bot), do: :ets.update_element(table, {shard_id, count}, {4, seq})
    :ok
  end

  @spec delete(term(), non_neg_integer(), pos_integer()) :: :ok
  def delete(bot, shard_id, count) do
    if table = table(bot), do: :ets.delete(table, {shard_id, count})
    :ok
  end

  @spec list(term()) :: [Lingo.Gateway.SessionStore.session()]
  def list(bot) do
    case table(bot) do
      nil -> []
      table -> table |> :ets.tab2list() |> Enum.map(&to_session/1) |> Enum.sort_by(& &1.shard_id)
    end
  end

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
    for session <- load(store, bot), valid?(session), do: insert(table, session)

    {:ok, %{bot: bot, store: store}}
  end

  @impl true
  def terminate(_reason, %{store: nil}), do: :ok

  def terminate(_reason, %{bot: bot, store: {module, opts}}) do
    module.save(bot, list(bot), opts)
  rescue
    e -> Logger.error("Lingo couldn't save gateway sessions: #{Exception.message(e)}")
  end

  defp load(nil, _bot), do: []

  defp load({module, opts}, bot) do
    module.load(bot, opts)
  rescue
    e ->
      Logger.error("Lingo couldn't load gateway sessions: #{Exception.message(e)}")
      []
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
