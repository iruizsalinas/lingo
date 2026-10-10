defmodule Lingo.Testing do
  @moduledoc """
  Testing a bot without Discord: interactions and events go through the
  bot's real callbacks, checks and collectors, and every API call it makes is
  recorded instead of sent.

      defmodule MyBotTest do
        use ExUnit.Case, async: true

        import Lingo.Testing

        setup do
          start_bot(MyBot)
          :ok
        end

        test "ping" do
          run_command("ping")
          assert %{type: :channel_message, data: %{"content" => "Pong!"}} = await_response()
        end

        test "echo" do
          run_command("echo", options: [text: "hi"], guild_id: nil)
          assert %{data: %{"content" => "hi"}} = await_response()
        end
      end

  Each test's bot is isolated, so tests can run async. API calls are
  answered `200` with `{}` (interaction callbacks `204`) unless `:rest`
  says otherwise.
  """

  import ExUnit.Callbacks, only: [start_supervised!: 1]

  alias Lingo.Instance
  alias Lingo.Testing.{Payload, Stub}

  @response_types %{
    1 => :pong,
    4 => :channel_message,
    5 => :deferred_channel_message,
    6 => :deferred_update_message,
    7 => :update_message,
    8 => :autocomplete,
    9 => :modal,
    12 => :launch_activity
  }

  @doc """
  Starts an isolated bot for the calling test, and makes it the current bot.
  Options: `:cache` (as for the bot), and `:rest`, a function getting each
  API call's method, path and decoded body and returning `{status, body}`.
  """
  @spec start_bot(module(), keyword()) :: atom()
  def start_bot(bot, opts \\ []) do
    name = Module.concat(bot, "Test#{System.unique_integer([:positive])}")

    config = [
      name: name,
      bot: bot,
      token: "test-token",
      http_request: Stub.new(self(), opts[:rest])
    ]

    children = [
      {Instance, config},
      {Task.Supervisor, name: Instance.process_name(name, Lingo.TaskSupervisor)},
      {Lingo.Cache.Tables, bot: name, config: opts[:cache]},
      {Lingo.Rest.RateLimiter, bot: name},
      {Registry, keys: :duplicate, name: Instance.process_name(name, Lingo.Collector.Registry)},
      {Lingo.Bot.Cooldowns, bot: name},
      {Lingo.Endpoint.Pending, bot: name}
    ]

    for child <- children,
        do: start_supervised!(Supervisor.child_spec(child, id: {name, child}))

    Instance.put(name, :application_id, "100")
    Lingo.put_bot(name)
    name
  end

  @doc """
  Runs a command. Options: `:options` (keyword, by the declared option
  names; subcommands nest: `[add: [item: "x"]]`), `:user_id` (default
  `"1"`), `:guild_id` (default `"2"`, `nil` for a DM), `:channel_id`,
  `:permissions` and `:app_permissions` (bitfields), `:locale`, and
  `:target_id` with `:type` (`:user` or `:message`) for context menu commands.
  """
  @spec run_command(String.t(), keyword()) :: :ok
  def run_command(name, opts \\ []), do: interaction(2, Payload.command(name, opts), opts)

  @doc """
  Runs autocomplete for a command, with the option being typed named by
  `:focused`. Takes the options of `run_command/2`.
  """
  @spec run_autocomplete(String.t(), keyword()) :: :ok
  def run_autocomplete(name, opts), do: interaction(4, Payload.autocomplete(name, opts), opts)

  @doc """
  Clicks a button, or picks `:values` in a select menu. Options: `:values`,
  `:message_id`, and those of `run_command/2`.
  """
  @spec run_component(String.t(), keyword()) :: :ok
  def run_component(custom_id, opts \\ []) do
    {data, message} = Payload.component(custom_id, opts)
    interaction(3, data, Keyword.put(opts, :message, message))
  end

  @doc "Submits a modal with text inputs keyed by custom id. Takes the options of `run_command/2`."
  @spec submit_modal(String.t(), %{String.t() => String.t()}, keyword()) :: :ok
  def submit_modal(custom_id, values, opts \\ []),
    do: interaction(5, Payload.modal(custom_id, values), opts)

  @doc "Delivers an event to the bot's `c:Lingo.Bot.handle_event/2`, as is."
  @spec send_event(atom(), term()) :: :ok
  def send_event(event, payload), do: Lingo.Bot.Runner.event(event, payload)

  @doc """
  Delivers a raw gateway dispatch, as Discord would send it: the cache is
  updated and the bot gets the parsed event. `type` is Discord's name,
  such as `"MESSAGE_CREATE"`.
  """
  @spec dispatch(String.t(), map()) :: :ok
  def dispatch(type, data) do
    data = data |> JSON.encode!() |> JSON.decode!()
    Lingo.Gateway.Dispatcher.dispatch(Lingo.Gateway.Events.name(type), data)
  end

  @doc """
  Waits for the bot to answer an interaction, and returns the answer:
  `%{type: :channel_message, data: %{"content" => ...}}` and so on. Raises
  if none comes within `timeout` ms.
  """
  @spec await_response(timeout()) :: %{type: atom(), data: map() | nil}
  def await_response(timeout \\ 1_000) do
    receive do
      {__MODULE__, %{method: :post, path: "/interactions/" <> rest, body: body}}
      when is_map(body) ->
        if String.ends_with?(rest, "/callback"),
          do: %{type: Map.get(@response_types, body["type"], body["type"]), data: body["data"]},
          else: await_response(timeout)
    after
      timeout -> raise ExUnit.AssertionError, message: "the bot didn't answer within #{timeout}ms"
    end
  end

  @doc """
  Waits for the next API call the bot makes, and returns its `:method`,
  `:path` (without `/api/v10`), `:query` and decoded `:body`.
  """
  @spec await_request(timeout()) :: map()
  def await_request(timeout \\ 1_000) do
    receive do
      {__MODULE__, request} -> request
    after
      timeout -> raise ExUnit.AssertionError, message: "no API call within #{timeout}ms"
    end
  end

  defp interaction(type, data, opts),
    do:
      Lingo.Gateway.Dispatcher.dispatch(
        :interaction_create,
        Payload.interaction(type, data, opts)
      )
end
