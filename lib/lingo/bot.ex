defmodule Lingo.Bot do
  @moduledoc """
  The behaviour for your bot module.

  A bot module declares its application commands and implements callbacks
  for whatever it wants to react to. Every callback is optional, and each
  call runs in its own supervised process.

      defmodule MyBot do
        use Lingo.Bot

        command "ping", "Responds with pong"

        command "ban", "Ban a user",
          default_member_permissions: Lingo.Permissions.from_list([:ban_members]),
          options: [
            user(:target, "Who to ban", required: true),
            string(:reason, "Why")
          ]

        @impl true
        def handle_command("ping", ctx), do: reply!(ctx, "Pong!")

        def handle_command("ban", ctx) do
          Lingo.Api.Ban.create(ctx.guild_id, option(ctx, :target), reason: option(ctx, :reason))
          ephemeral!(ctx, "Banned.")
        end

        @impl true
        def handle_component("vote:" <> choice, ctx), do: update!(ctx, "You voted \#{choice}")

        @impl true
        def handle_event(:message_create, %{content: "hello"} = msg),
          do: Lingo.Api.Message.create(msg.channel_id, "Hello back!")
      end

  `use Lingo.Bot` imports the declaration macros from `Lingo.Bot.Commands`,
  the option builders from `Lingo.Bot.Options` and the functions of
  `Lingo.Context`. If your module calls a function of its own with the same
  name, such as `get_user/2`, leave that one out:

      use Lingo.Bot
      import Lingo.Context, except: [get_user: 2]

  You only write the clauses you care about: anything that matches none of
  them is ignored (an unknown command is logged). When you don't implement
  `c:handle_component/2` or `c:handle_modal/2` at all, those interactions
  reach `c:handle_event/2` as `:interaction_create` instead.

  ## Starting

  `use Lingo.Bot` gives your module `child_spec/1` and `start_link/1`, so it
  goes straight into a supervision tree:

      children = [
        {MyBot, token: System.fetch_env!("BOT_TOKEN"), intents: [:guilds, :guild_messages]}
      ]

  Options:

    * `:token` (required) - the bot token
    * `:name` - names this bot, for `Lingo.with_bot/2`; defaults to the module.
      Lets one module run as several bots.
    * `:intents` - gateway intents, as atoms or a bitfield
      (default `[:guilds, :guild_messages]`)
    * `:register_commands` - registers the declared commands once all shards
      are ready: `:global`, `{:guild, id}` or `{:guilds, ids}` (default
      `false`). `Lingo.register_commands/1` does it on demand.
    * `:cache` - which resources to cache and their policies; nothing is
      cached by default. See `Lingo.Cache`.
    * `:sharding` - `:count` (default `:auto`); `:ids`, the shards this
      node runs (needs `:count`); `:auto_reshard`, `true` (checks hourly) or
      an interval in ms, to reshard when Discord recommends more shards.
      See `Lingo.Gateway`.
    * `:endpoint` - receives interactions and webhook events over HTTP; see
      `Lingo.Endpoint`
    * `:gateway` - `false` to run without a gateway connection (see
      `Lingo.Endpoint`), or `:encoding` (`:json`, the default, or `:etf`),
      `:compression` (`:zlib`, the default, `:zstd` on OTP 28+, or `:none`)
      and `:session_store`, a `Lingo.Gateway.SessionStore` module or
      `{module, opts}` to resume sessions after a restart
    * `:presence` - the initial `:status`, `:text` and `:activity`
    * `:rate_limit` - `:max_wait`, the longest an API call waits on rate
      limits in ms (default `:infinity`, see `Lingo.with_max_wait/2`)
    * `:rest` - `:base_url`, to send API calls through a REST proxy that
      handles rate limits for every node and process, such as
      `"http://proxy.internal/api/v10"` (default Discord's API). Each node
      still follows the limits the proxy's answers carry, but stops sharing
      them with the other nodes, which the proxy does.
  """

  alias Lingo.Context

  @doc """
  Handles a slash command or context menu command, by command name.

  For subcommands the name is the top-level command; the chosen subcommand
  is a key in `ctx.options`.
  """
  @callback handle_command(name :: String.t(), ctx :: Context.t()) :: term()

  @doc "Handles a click or selection on a message component, by its custom id."
  @callback handle_component(custom_id :: String.t(), ctx :: Context.t()) :: term()

  @doc "Handles a modal submission, by the modal's custom id."
  @callback handle_modal(custom_id :: String.t(), ctx :: Context.t()) :: term()

  @doc """
  Handles an autocomplete request for a command option declared with
  `autocomplete: true`. Answer with `Lingo.Context.autocomplete_result/2`.
  """
  @callback handle_autocomplete(command_name :: String.t(), ctx :: Context.t()) :: term()

  @doc """
  Handles an event Discord sends, such as `:message_create` or
  `:guild_member_add`, named as Discord names it, lowercased.

  Creates carry the resource, such as a `Lingo.Type.Message`; updates
  `%{old: old, new: new}`, where `old` comes from the cache and is `nil` when
  it wasn't cached; other events a struct of their own, such as
  `Lingo.Event.MessageDelete`. `Lingo.Event` lists every event and its
  payload.
  """
  @callback handle_event(event :: Lingo.Event.name(), payload :: Lingo.Event.payload()) ::
              term()

  @doc """
  Handles a failure in one of the bot's callbacks: a crash, or a command that
  didn't pass its checks or is on cooldown.

  `source` is the `Lingo.Context` for interactions, and `{event, payload}`
  for events. `error` is the exception (exits and throws arrive as
  `ErlangError`), a `Lingo.CheckError` for a failed check, or a
  `Lingo.EventError` for an event Lingo couldn't parse, which never reaches
  `c:handle_event/2` (its `payload` is then Discord's raw data). Crashes are
  logged either way; for a failed check nothing is answered unless you do:

      def handle_error(%Lingo.CheckError{message: message}, ctx), do: ephemeral(ctx, message)
      def handle_error(_error, %Lingo.Context{} = ctx), do: ephemeral(ctx, "Something went wrong.")
      def handle_error(_error, _event), do: :ok

  Without it, a failed check gets the error's message as an ephemeral reply.
  """
  @callback handle_error(
              error :: Exception.t(),
              source :: Context.t() | {Lingo.Event.name(), term()}
            ) :: term()

  @optional_callbacks handle_command: 2,
                      handle_error: 2,
                      handle_component: 2,
                      handle_modal: 2,
                      handle_autocomplete: 2,
                      handle_event: 2

  defmacro __using__(_opts) do
    quote do
      @behaviour Lingo.Bot

      import Lingo.Bot.Commands, only: :macros
      import Lingo.Bot.Options
      import Lingo.Context, except: [new: 1, new: 2]

      Module.register_attribute(__MODULE__, :lingo_commands, accumulate: true)
      Module.register_attribute(__MODULE__, :lingo_command_rules, accumulate: true)

      @doc false
      def child_spec(opts), do: Lingo.Supervisor.child_spec(__MODULE__, opts)

      @doc false
      def start_link(opts), do: Lingo.Supervisor.start_link(__MODULE__, opts)

      defoverridable child_spec: 1, start_link: 1

      @before_compile Lingo.Bot.Compiler
    end
  end
end
