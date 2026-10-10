defmodule Lingo do
  @moduledoc """
  A Discord library: the gateway, the REST API, interactions and voice.

  Write a bot module with `Lingo.Bot`, then add it to your supervision tree
  (the options are listed in `Lingo.Bot`):

      children = [
        {MyBot,
         token: System.fetch_env!("BOT_TOKEN"),
         intents: [:guilds, :guild_messages, :message_content],
         register_commands: :global}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  ## Where things are

    * `Lingo.Api.*` - the REST API, one module per resource, such as
      `Lingo.Api.Message.create/2` (errors are `Lingo.Error`)
    * `Lingo.Cache.*` - what the gateway and REST API have told the bot, such as
      `Lingo.Cache.Role.list/1` (opt-in, see `Lingo.Cache`)
    * `Lingo.Gateway` - presence, shards and gateway requests
    * `Lingo.Voice` - joining voice channels, playing and receiving audio
    * `Lingo.Component` and `Lingo.Embed` - building message content

  ## Which bot a call goes to

  Calls such as `Lingo.Api.Message.create/2` don't take a bot argument; they
  go to the current bot, found in this order:

    1. the bot chosen in this process with `with_bot/2` or `put_bot/1`. Every
       process Lingo starts for a bot, including the ones running your
       callbacks, has it set.
    2. the bot of a process that started this one through `Task` (`Task.async/1`,
       `Task.Supervisor`...), since tasks know their callers.
    3. the only running bot. With none, or several, the call raises
       `ArgumentError`.

  With one bot you never need to think about it. With several, choose one
  wherever step 1 and 2 don't apply: processes you start with `spawn/1`, and
  your own GenServers, which don't inherit it even when started from a
  callback. Call `put_bot/1` in their `c:GenServer.init/1`.

  A `Lingo.Context` carries its bot, so an interaction can be answered from
  any process.
  """

  @doc """
  Runs `fun` with calls going to the bot named `name`. Only needed when
  running several bots, outside the processes Lingo starts for them.

      Lingo.with_bot(SupportBot, fn -> Lingo.Api.Message.create(channel_id, "Hi") end)
  """
  @spec with_bot(atom(), (-> result)) :: result when result: any()
  def with_bot(name, fun) when is_atom(name) and is_function(fun, 0),
    do: Lingo.Instance.with_current(name, fun)

  @doc """
  Makes calls from this process go to the bot named `name`; returns the
  previous choice. Use it in processes Lingo doesn't start, such as your own
  GenServers when running several bots.

      def init(opts) do
        Lingo.put_bot(SupportBot)
        {:ok, opts}
      end
  """
  @spec put_bot(atom()) :: atom() | nil
  def put_bot(name) when is_atom(name), do: Lingo.Instance.put_current(name)

  @doc "The names of the running bots."
  @spec bots() :: [atom()]
  def bots, do: Lingo.Instance.running()

  @doc """
  Caps how long the API calls `fun` makes may wait on rate limits, in ms.

  Calls that would wait longer return `{:error, %Lingo.Error{reason: :rate_limited}}`
  instead of blocking. Only applies to the calling process.
  """
  @spec with_max_wait(non_neg_integer() | :infinity, (-> result)) :: result when result: any()
  defdelegate with_max_wait(max_wait, fun), to: Lingo.Rest.Client

  @doc """
  Sends the bot's declared commands to Discord, replacing the ones there.

  `scope` is `:global` (the default), `{:guild, guild_id}` or
  `{:guilds, guild_ids}`. Guild commands update instantly, which helps during
  development.
  """
  @spec register_commands(:global | {:guild, String.t()} | {:guilds, [String.t()]}) ::
          {:ok, [Lingo.Type.ApplicationCommand.t()]} | {:error, Lingo.Error.t()}
  def register_commands(scope \\ :global), do: Lingo.Bot.Sync.register(scope)
end
