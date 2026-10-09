defmodule Lingo.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    token = Keyword.fetch!(opts, :token)
    bot_module = Keyword.fetch!(opts, :bot_module)
    intents = Keyword.get(opts, :intents, [:guilds, :guild_messages])

    Lingo.Config.put(:token, token)
    Lingo.Config.put(:bot_module, bot_module)
    Lingo.Config.put(:intents, intents)
    Lingo.Config.put(:max_wait, opts |> Keyword.get(:rate_limit, []) |> Keyword.get(:max_wait))

    cache_opts = Keyword.get(opts, :cache, [])
    sharding = Keyword.get(opts, :sharding, [])
    presence = Keyword.get(opts, :presence, [])

    children = [
      {Lingo.Cache, cache_opts},
      Lingo.Api.RateLimiter,
      {Registry, keys: :duplicate, name: Lingo.Collector.Registry},
      {DynamicSupervisor, name: Lingo.Voice.Supervisor, strategy: :one_for_one},
      Lingo.Voice.Manager,
      {Lingo.Gateway.ShardManager,
       token: token, intents: intents, sharding: sharding, presence: presence}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
