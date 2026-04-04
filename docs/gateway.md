# Gateway

Functions for gateway operations. All are on the `Lingo` module.

## Presence

### `update_presence(status, opts \\ [])`

Update the bot's presence across all shards.

```elixir
Lingo.update_presence(:online, text: "with Elixir")
Lingo.update_presence(:dnd)
Lingo.update_presence(:idle, activity: %Lingo.Type.Activity{name: "music", type: :listening})
```

| Param | Type | Description |
|-------|------|-------------|
| `status` | atom | `:online`, `:idle`, `:dnd`, `:invisible` |
| `text` | string | Sets a "Playing" activity |
| `activity` | `Activity` struct | Full activity control |

### Activity Types

| Type | Display |
|------|---------|
| `:playing` | "Playing {name}" |
| `:streaming` | "Streaming {name}" (requires `url`) |
| `:listening` | "Listening to {name}" |
| `:watching` | "Watching {name}" |
| `:custom` | "{state}" or "{emoji} {state}" |
| `:competing` | "Competing in {name}" |

## Voice

### `join_voice(guild_id, channel_id, opts \\ [])`

Join a voice channel. `opts`: `self_mute:` (boolean), `self_deaf:` (boolean).

```elixir
Lingo.join_voice(guild_id, voice_channel_id, self_deaf: true)
```

### `leave_voice(guild_id)`

Leave the voice channel in a guild.

Lingo doesn't handle voice audio. These functions send the gateway opcode to join/leave. Use a separate library for audio.

## Guild Members

### `request_guild_members(guild_id, opts \\ [])`

Request guild members through the gateway. Responses arrive as `:guild_members_chunk` events.

```elixir
# Request all members
Lingo.request_guild_members(guild_id)

# Search by prefix
Lingo.request_guild_members(guild_id, query: "John", limit: 10)

# Request specific users
Lingo.request_guild_members(guild_id, user_ids: ["123", "456"])

# Include presences
Lingo.request_guild_members(guild_id, presences: true)

# With a nonce for tracking
Lingo.request_guild_members(guild_id, nonce: "my_request_1")
```

Handle the response:

```elixir
handle :guild_members_chunk, data do
  IO.puts("Received #{length(data.members)} members (#{data.chunk_index + 1}/#{data.chunk_count})")
end
```

## Soundboard

### `request_soundboard_sounds(guild_ids)`

Request soundboard sounds for the given guild IDs. Responses arrive as `:soundboard_sounds` events.

```elixir
Lingo.request_soundboard_sounds(["guild_id_1", "guild_id_2"])
```

## Sharding

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
