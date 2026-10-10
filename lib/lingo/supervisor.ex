defmodule Lingo.Supervisor do
  @moduledoc false

  use Supervisor

  alias Lingo.Instance

  # what a bot module's generated child_spec/1 and start_link/1 call
  def child_spec(bot, opts) do
    opts = Lingo.Config.validate!(Keyword.put(opts, :bot, bot))
    %{id: opts[:name], start: {__MODULE__, :start_link, [opts]}, type: :supervisor}
  end

  def start_link(bot, opts),
    do: opts |> Keyword.put(:bot, bot) |> Lingo.Config.validate!() |> start_link()

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, opts, name: Instance.process_name(name, __MODULE__))
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    bot = Keyword.fetch!(opts, :bot)
    Code.ensure_loaded!(bot)

    config = [
      name: name,
      bot: bot,
      token: Keyword.fetch!(opts, :token),
      intents: opts[:intents],
      max_wait: get_in(opts, [:rate_limit, :max_wait]),
      rest_base_url: get_in(opts, [:rest, :base_url]),
      register_commands: opts[:register_commands],
      endpoint: opts[:endpoint],
      # tests stand in for Discord here
      http_request: opts[:http_request]
    ]

    children = [
      {Instance, config},
      {Task.Supervisor, name: Instance.process_name(name, Lingo.TaskSupervisor)},
      {Lingo.Cache.Tables, bot: name, config: opts[:cache]},
      {Lingo.Rest.RateLimiter, bot: name},
      {Registry, keys: :duplicate, name: Instance.process_name(name, Lingo.Collector.Registry)},
      {DynamicSupervisor,
       name: Instance.process_name(name, Lingo.Voice.Supervisor), strategy: :one_for_one},
      {Lingo.Voice.Manager, bot: name},
      {Lingo.Bot.Cooldowns, bot: name},
      {Lingo.Endpoint.Pending, bot: name},
      {Lingo.Gateway.Groups, bot: name}
    ]

    children = children ++ gateway(name, config, opts) ++ endpoint(name, opts[:endpoint])

    # everything after Instance reads the config it owns (table references
    # included), so a restarted Instance restarts them too
    Supervisor.init(children, strategy: :rest_for_one)
  end

  # without a gateway nothing fires :ready, so commands register at start
  defp gateway(name, config, opts) do
    if opts[:gateway] == false do
      [Supervisor.child_spec({Task, fn -> register_commands(name) end}, restart: :temporary)]
    else
      [
        # sessions start before the shard manager so they're saved after it stops
        {Lingo.Gateway.Sessions, bot: name, store: get_in(opts, [:sharding, :session_store])},
        {Lingo.Gateway.Identify, bot: name},
        {Lingo.Gateway.ShardManager,
         bot: name,
         token: config[:token],
         intents: opts[:intents],
         sharding: opts[:sharding],
         gateway: opts[:gateway],
         presence: opts[:presence]}
      ]
    end
  end

  defp endpoint(name, endpoint) do
    if endpoint[:port], do: [{Lingo.Endpoint.Server, bot: name, endpoint: endpoint}], else: []
  end

  defp register_commands(name) do
    Instance.put_current(name)
    Lingo.Bot.Sync.register_on_ready()
  end
end
