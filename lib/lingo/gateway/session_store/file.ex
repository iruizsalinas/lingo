defmodule Lingo.Gateway.SessionStore.File do
  @moduledoc """
  A `Lingo.Gateway.SessionStore` that keeps sessions in a local file, for a
  bot that restarts on the same machine.

  Options: `:path` (required).
  """

  @behaviour Lingo.Gateway.SessionStore

  @impl true
  def load(_bot, opts), do: opts |> read() |> Map.values()

  @impl true
  def save(_bot, session, opts) do
    opts
    |> read()
    |> Map.put({session.shard_id, session.shard_count}, session)
    |> write(opts)
  end

  @impl true
  def delete(_bot, shard_id, shard_count, opts) do
    sessions = read(opts)

    if Map.has_key?(sessions, {shard_id, shard_count}),
      do: write(Map.delete(sessions, {shard_id, shard_count}), opts),
      else: :ok
  end

  # sessions by {shard_id, shard_count}
  defp read(opts) do
    with {:ok, data} <- File.read(Keyword.fetch!(opts, :path)),
         sessions when is_map(sessions) <- :erlang.binary_to_term(data, [:safe]) do
      sessions
    else
      _missing_or_invalid -> %{}
    end
  rescue
    ArgumentError -> %{}
  end

  # written aside and renamed, so a crash mid-write never leaves half a file
  defp write(sessions, opts) do
    path = Keyword.fetch!(opts, :path)
    tmp = path <> ".tmp"

    with :ok <- File.write(tmp, :erlang.term_to_binary(sessions)),
         :ok <- File.rename(tmp, path) do
      :ok
    end
  end
end
