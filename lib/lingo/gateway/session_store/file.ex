defmodule Lingo.Gateway.SessionStore.File do
  @moduledoc """
  A `Lingo.Gateway.SessionStore` that keeps sessions in a local file, for a
  bot that restarts on the same machine.

  Options: `:path` (required).
  """

  @behaviour Lingo.Gateway.SessionStore

  @impl true
  def load(_bot, opts) do
    with {:ok, data} <- File.read(Keyword.fetch!(opts, :path)),
         sessions when is_list(sessions) <- :erlang.binary_to_term(data, [:safe]) do
      sessions
    else
      _missing_or_invalid -> []
    end
  rescue
    ArgumentError -> []
  end

  @impl true
  def save(_bot, sessions, opts) do
    path = Keyword.fetch!(opts, :path)
    tmp = path <> ".tmp"

    # written aside and renamed, so a crash mid-write never leaves half a file
    with :ok <- File.write(tmp, :erlang.term_to_binary(sessions)),
         :ok <- File.rename(tmp, path) do
      :ok
    end
  end
end
