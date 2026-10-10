defmodule Lingo.Gateway.SessionStore do
  @moduledoc """
  Keeps gateway sessions across restarts of the whole bot, so a redeployed
  bot resumes its shards instead of identifying them again.

  Shards that crash or restart while the bot runs always resume; a store is
  only needed to carry sessions over a full stop. Give one with the
  `:sharding` option:

      sharding: [session_store: {Lingo.Gateway.SessionStore.File, path: "sessions.bin"}]

  The bot calls `c:load/2` when it starts and `c:save/3` when it stops,
  after its shards have closed. Discord keeps a session resumable for only a
  few minutes after its connection drops, and replays the events missed in
  between.

  A resumed session doesn't send `GUILD_CREATE` again, so a cache that
  starts empty stays without the guilds it already had: use a store with
  caching off, or when that's acceptable.
  """

  @typedoc "One shard's session."
  @type session :: %{
          shard_id: non_neg_integer(),
          shard_count: pos_integer(),
          session_id: String.t(),
          resume_gateway_url: String.t(),
          seq: non_neg_integer()
        }

  @doc "Returns the sessions saved for the bot named `bot`."
  @callback load(bot :: term(), opts :: keyword()) :: [session()]

  @doc "Saves the bot's sessions, replacing any saved before."
  @callback save(bot :: term(), [session()], opts :: keyword()) :: :ok
end
