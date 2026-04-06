# Sharding

Lingo handles sharding automatically by asking the gateway for the recommended shard count.

## Configuration

```elixir
# Auto (default)
{Lingo, bot: MyBot.Bot, token: token, intents: intents}

# Fixed shard count
{Lingo, bot: MyBot.Bot, token: token, intents: intents,
 sharding: [count: 4]}

# Specific shards for multi-node setups (count is required with ids)
{Lingo, bot: MyBot.Bot, token: token, intents: intents,
 sharding: [count: 4, ids: [0, 1]]}
```

| Option | Type | Default |
|--------|------|---------|
| `count` | `integer \| :auto` | `:auto` |
| `ids` | `[integer] \| :all` | `:all` |

## Shard Management

### `shard_count()`

Returns the total number of shards.

### `shard_for_guild(guild_id)`

Returns the shard ID that handles a guild.

### `restart_shard(shard_id)`

Restart a specific shard. Returns `:ok` or `{:error, reason}`.

### `reshard()`

Re-query Discord for the recommended shard count and restart all shards. Only works with auto shard count (no manual `count:` configured).

### `latency(shard_id)`

Returns the last heartbeat round-trip time in milliseconds, or `nil`.

### `latencies()`

Returns a map of `%{shard_id => latency_ms}` for all shards.

## Multi-Node

For running across multiple nodes, give each node a different subset of shard IDs with the same total count:

```elixir
# Node A
{Lingo, bot: MyBot.Bot, token: token, intents: intents,
 sharding: [count: 4, ids: [0, 1]]}

# Node B
{Lingo, bot: MyBot.Bot, token: token, intents: intents,
 sharding: [count: 4, ids: [2, 3]]}
```
