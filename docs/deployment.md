# Deployment & Configuration

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `bot` | module | **required** | Bot module with `use Lingo.Bot` |
| `token` | string | **required** | Bot token |
| `intents` | `[atom] \| integer` | `[:guilds, :guild_messages]` | Gateway intents |
| `cache` | `keyword \| false` | `[]` | Cache config, or `false` to disable (see [Cache](/cache#configuration)) |
| `sharding` | keyword | `[]` | Sharding config (see below) |
| `presence` | keyword | `[]` | Initial presence (see below) |

## Sharding

Lingo handles sharding automatically by asking the gateway for the recommended shard count.

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

### Shard Management

```elixir
Lingo.shard_count()                    # total shard count
Lingo.shard_for_guild(guild_id)        # which shard handles this guild
Lingo.restart_shard(shard_id)          # restart a specific shard
Lingo.reshard()                        # re-query and restart all shards
Lingo.latency(shard_id)               # heartbeat latency in ms
Lingo.latencies()                      # %{shard_id => latency_ms} for all shards
```

`reshard/0` only works with auto shard count. If you set a manual count, it's a no-op.

## Presence

Set the bot's status on connect:

```elixir
{Lingo,
 bot: MyBot.Bot,
 token: token,
 intents: intents,
 presence: [status: :online, text: "with Elixir"]}
```

| Option | Type | Default |
|--------|------|---------|
| `status` | atom | `:online` |
| `text` | string | `nil` |
| `activity` | `Activity` struct | `nil` |

`text` sets a "Playing" activity. For more control, pass a struct:

```elixir
presence: [
  status: :dnd,
  activity: %Lingo.Type.Activity{name: "music", type: :listening}
]
```

Activity types: `:playing`, `:streaming`, `:listening`, `:watching`, `:custom`, `:competing`.

Status values: `:online`, `:idle`, `:dnd`, `:invisible`.

### Updating at Runtime

```elixir
Lingo.update_presence(:online, text: "something new")
Lingo.update_presence(:idle)
Lingo.update_presence(:dnd, activity: %Lingo.Type.Activity{name: "music", type: :listening})
```

Broadcasts to all shards.
