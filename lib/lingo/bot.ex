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
    * `:sharding` - `:count` (default `:auto`) and `:ids`, the shards this
      node runs (needs `:count`)
    * `:presence` - the initial `:status`, `:text` and `:activity`
    * `:rate_limit` - `:max_wait`, the longest an API call waits on rate
      limits in ms (default `:infinity`, see `Lingo.with_max_wait/2`)
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
  Handles a gateway event, such as `:message_create` or `:guild_member_add`.

  Event names are Discord's, lowercased. Create events carry the new struct,
  update and delete events a map with `:old` (from the cache, or `nil`) and
  `:new`. Lingo adds `:ready` (all shards connected), `:shard_ready`,
  `:shard_resumed` and `:rate_limit`.
  """
  @callback handle_event(event :: atom(), payload :: term()) :: term()

  @optional_callbacks handle_command: 2,
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

      @doc false
      def child_spec(opts), do: Lingo.Supervisor.child_spec(__MODULE__, opts)

      @doc false
      def start_link(opts), do: Lingo.Supervisor.start_link(__MODULE__, opts)

      defoverridable child_spec: 1, start_link: 1

      @before_compile Lingo.Bot.Compiler
    end
  end
end
