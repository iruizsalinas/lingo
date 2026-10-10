defmodule Lingo.Gateway do
  @moduledoc """
  The bot's gateway connection: presence, requests sent over the gateway,
  and its shards.

  Answers to gateway requests arrive later, as events for
  `c:Lingo.Bot.handle_event/2`.

  ## Large bots

    * **Resuming.** A shard that crashes or restarts resumes its session
      instead of identifying again, so no events are lost and no identify is
      spent. To carry sessions over a full restart (a redeploy), give a
      `Lingo.Gateway.SessionStore`.
    * **Identify limits.** Shards identify in their `max_concurrency` bucket
      order, and never past the daily limit (going over it resets the token):
      once it's spent they wait for it to reset.
    * **Resharding without downtime.** `reshard/0`, or `auto_reshard: true`
      under `:sharding`, brings up the new shards next to the running ones,
      and switches over once all are ready.
    * **Several nodes.** Run one bot on connected nodes by giving each the
      same `:name` and `:count`, and its own `:ids`. The nodes share the
      identify limits, and gateway requests reach the node that runs the
      guild's shard; `update_presence/2` reaches every node. Shard statuses
      and latencies are this node's.
    * **Encoding and compression.** `gateway: [encoding: :etf]` receives
      Erlang terms instead of JSON. `compression: :zstd` (OTP 28 or later)
      uses less CPU than the default `:zlib`; `:none` turns it off.

  `Lingo.Telemetry` lists the events to watch all this with.
  """

  alias Lingo.Gateway.{Heartbeat, Payload, Sessions, ShardManager}

  @doc """
  Sets the bot's status (`:online`, `:idle`, `:dnd` or `:invisible`) on every
  shard, with an optional `text:` or `activity:`.
  """
  @spec update_presence(atom(), keyword()) :: :ok
  def update_presence(status, opts \\ []),
    do: ShardManager.update_presence(status: status, text: opts[:text], activity: opts[:activity])

  @doc """
  Asks for a guild's members. They arrive as `:guild_members_chunk` events
  and fill the cache. Options: `:query`, `:limit`, `:presences`,
  `:user_ids` and `:nonce`.
  """
  @spec request_guild_members(String.t(), keyword()) :: :ok
  def request_guild_members(guild_id, opts \\ []),
    do: ShardManager.send_to_guild_shard(guild_id, Payload.request_guild_members(guild_id, opts))

  @doc "Asks for the soundboard sounds of some guilds. They arrive as `:soundboard_sounds` events."
  @spec request_soundboard_sounds([String.t()]) :: :ok
  def request_soundboard_sounds(guild_ids) when is_list(guild_ids),
    do: ShardManager.broadcast(Payload.request_soundboard_sounds(guild_ids))

  @doc "Asks for extra channel info, like voice channel statuses. It arrives as `:channel_info`."
  @spec request_channel_info(String.t(), [String.t()]) :: :ok
  def request_channel_info(guild_id, fields \\ ["status", "voice_start_time"]),
    do: ShardManager.send_to_guild_shard(guild_id, Payload.request_channel_info(guild_id, fields))

  @doc "The shard a guild's events arrive on."
  @spec shard_for_guild(String.t()) :: non_neg_integer()
  defdelegate shard_for_guild(guild_id), to: ShardManager

  @doc "How many shards the bot runs in total."
  @spec shard_count() :: non_neg_integer()
  defdelegate shard_count, to: ShardManager

  @doc "The connection state of a shard, such as `:connected`, or `:dead`."
  @spec shard_status(non_neg_integer()) :: atom()
  defdelegate shard_status(shard_id), to: ShardManager

  @doc "The connection state of every shard."
  @spec shard_statuses() :: %{non_neg_integer() => atom()}
  defdelegate shard_statuses, to: ShardManager

  @doc "Reconnects a shard from scratch, identifying again."
  @spec restart_shard(non_neg_integer()) :: :ok | {:error, term()}
  defdelegate restart_shard(shard_id), to: ShardManager

  @doc """
  Asks Discord for the recommended shard count and, when it differs, moves
  to it without downtime: the new shards connect next to the running ones,
  delivering nothing, and take over once all are ready (events at the very
  moment of the switch may arrive twice or not at all). The old shards then
  close. `:ready` doesn't fire again.

  Does nothing when the count or the ids are fixed, while a reshard is under
  way, or when the day's identifies wouldn't cover the new shards. A reshard
  whose shards don't all get ready in time is abandoned.
  """
  @spec reshard() :: :ok
  defdelegate reshard, to: ShardManager

  @doc """
  The sessions of the shards on this node, as a `Lingo.Gateway.SessionStore`
  saves them.
  """
  @spec sessions() :: [Lingo.Gateway.SessionStore.session()]
  def sessions, do: Sessions.list(Lingo.Instance.current())

  @doc "A shard's last heartbeat round trip in ms, or `nil`."
  @spec latency(non_neg_integer()) :: non_neg_integer() | nil
  defdelegate latency(shard_id), to: Heartbeat

  @doc "Every shard's last heartbeat round trip in ms."
  @spec latencies() :: %{non_neg_integer() => non_neg_integer()}
  defdelegate latencies, to: Heartbeat
end
