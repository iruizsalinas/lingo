defmodule Lingo.TestBot do
  @moduledoc false

  # Starts the pieces of a bot a test needs, under the test's supervisor and
  # with a unique name, so tests stay isolated and can run async.

  import ExUnit.Callbacks, only: [start_supervised!: 1]

  alias Lingo.Instance

  @services [:cache, :rate_limiter, :collector, :identify, :sessions, :pending, :cooldowns]

  @doc """
  Options: `:bot` (module), `:token`, `:http_request`, `:application_id`,
  `:user_id`, `:max_wait`, `:test_pid`, `:cache` (cache config) and `:start` (services to
  run: #{inspect(@services)}).
  """
  def start(opts \\ []) do
    name = Module.concat(__MODULE__, "Bot#{System.unique_integer([:positive])}")

    config =
      opts
      |> Keyword.take([:bot, :http_request, :application_id, :user_id, :max_wait, :test_pid])
      |> Keyword.merge(name: name, token: Keyword.get(opts, :token, "test-token"))

    start_child({Instance, config}, name)
    start_child({Task.Supervisor, name: Instance.process_name(name, Lingo.TaskSupervisor)}, name)

    for service <- Keyword.get(opts, :start, []) do
      start_child(child_spec(service, name, opts), name)
    end

    Lingo.put_bot(name)
    name
  end

  defp start_child(spec, name) do
    spec = Supervisor.child_spec(spec, [])
    start_supervised!(%{spec | id: {spec.id, name}})
  end

  defp child_spec(:cache, name, opts), do: {Lingo.Cache.Tables, bot: name, config: opts[:cache]}
  defp child_spec(:rate_limiter, name, _opts), do: {Lingo.Rest.RateLimiter, bot: name}

  defp child_spec(:collector, name, _opts),
    do: {Registry, keys: :duplicate, name: Instance.process_name(name, Lingo.Collector.Registry)}

  # identifies are always available right away
  defp child_spec(:identify, name, _opts),
    do:
      {Lingo.Gateway.Identify,
       bot: name, plan: %{max_concurrency: 16, remaining: 1_000, reset_after: 0}}

  defp child_spec(:sessions, name, _opts), do: {Lingo.Gateway.Sessions, bot: name}
  defp child_spec(:pending, name, _opts), do: {Lingo.Endpoint.Pending, bot: name}
  defp child_spec(:cooldowns, name, _opts), do: {Lingo.Bot.Cooldowns, bot: name}
end
