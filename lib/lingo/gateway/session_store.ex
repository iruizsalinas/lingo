defmodule Lingo.Gateway.SessionStore do
  @moduledoc """
  Keeps gateway sessions across restarts of the whole bot, so a redeployed
  bot resumes its shards instead of identifying them again.

  Shards that crash or restart while the bot runs always resume; a store is
  only needed to carry sessions over a full stop. Give one with the
  `:gateway` option:

      gateway: [session_store: {Lingo.Gateway.SessionStore.File, path: "sessions.bin"}]

  The bot calls `c:load/2` once when it starts. It calls `c:save/3` for a
  shard whenever its session starts or resumes, and for every shard when
  the bot stops, after they've closed, with their last sequence numbers; and
  `c:delete/4` when a session can't be resumed anymore. Discord keeps a
  session resumable for only a few minutes after its connection drops, and
  replays the events missed in between.

  Calls come from one process per bot, one at a time, never from the shards
  themselves, so a slow store doesn't hold up the gateway. A store that
  raises is logged and otherwise ignored. Each shard is saved on its own,
  so the nodes of a bot split across several (see `Lingo.Gateway`) can
  share a store without overwriting each other's sessions; when they do,
  each node loads only the sessions of its own `:ids`.

  A resumed session doesn't send `GUILD_CREATE` again, so a cache that
  starts empty stays without the guilds it already had: use a store with
  caching off, or when that's acceptable (Lingo warns when both are on).
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

  @doc "Saves one shard's session, replacing the one saved for that shard before."
  @callback save(bot :: term(), session(), opts :: keyword()) :: :ok

  @doc "Forgets a shard's session."
  @callback delete(
              bot :: term(),
              shard_id :: non_neg_integer(),
              shard_count :: pos_integer(),
              opts :: keyword()
            ) :: :ok
end
