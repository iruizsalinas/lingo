defmodule Lingo.Gateway.Shard do
  @moduledoc false

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    shard_id = Keyword.fetch!(opts, :shard_id)
    shard_count = Keyword.fetch!(opts, :shard_count)
    token = Keyword.fetch!(opts, :token)
    intents = Keyword.fetch!(opts, :intents)
    gateway_url = Keyword.get(opts, :gateway_url)
    presence = Keyword.get(opts, :presence, [])

    children = [
      {Lingo.Gateway.Connection,
       shard_id: shard_id,
       shard_count: shard_count,
       token: token,
       intents: intents,
       gateway_url: gateway_url,
       presence: presence}
    ]

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
  end
end
