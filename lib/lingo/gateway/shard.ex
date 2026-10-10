defmodule Lingo.Gateway.Shard do
  @moduledoc false

  # Supervises one shard's gateway connection, and finds it for the manager.

  use Supervisor

  alias Lingo.Gateway.Connection

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    connection =
      {Connection,
       bot: Keyword.fetch!(opts, :bot),
       shard_id: Keyword.fetch!(opts, :shard_id),
       shard_count: Keyword.fetch!(opts, :shard_count),
       token: Keyword.fetch!(opts, :token),
       intents: Keyword.fetch!(opts, :intents),
       gateway_url: Keyword.get(opts, :gateway_url),
       presence: Keyword.get(opts, :presence, [])}

    Supervisor.init([connection], strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
  end

  @doc "The shard's connection process, or nil while it restarts."
  @spec connection(pid()) :: pid() | nil
  def connection(shard) do
    if Process.alive?(shard) do
      Enum.find_value(Supervisor.which_children(shard), fn
        {_, pid, :worker, [Connection]} when is_pid(pid) -> pid
        _ -> nil
      end)
    end
  rescue
    _ -> nil
  end

  @spec status(pid()) :: atom()
  def status(shard) do
    case connection(shard) do
      nil -> :dead
      pid -> Connection.status(pid)
    end
  end

  @spec send_payload(pid(), map()) :: :ok
  def send_payload(shard, payload) do
    if pid = connection(shard), do: Connection.send_payload(pid, payload)
    :ok
  end
end
