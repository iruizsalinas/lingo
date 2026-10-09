# Commands

## Voice

### `join_voice(guild_id, channel_id, opts \\ [])`

Join a voice channel and wait until the voice connection is up. `opts`: `self_mute:` (boolean), `self_deaf:` (boolean), `timeout:` (milliseconds).

```elixir
{:ok, _connection} = Lingo.join_voice(guild_id, voice_channel_id, self_deaf: true)
```

### `leave_voice(guild_id)`

Leave the voice channel in a guild.

These are shortcuts for `Lingo.Voice.join/3` and `Lingo.Voice.leave/1`. See [Voice](/voice) for playing and receiving audio.

## Guild Members

### `request_guild_members(guild_id, opts \\ [])`

Request guild members through the gateway. Responses arrive as `:guild_members_chunk` events.

```elixir
Lingo.request_guild_members(guild_id)
Lingo.request_guild_members(guild_id, query: "John", limit: 10)
Lingo.request_guild_members(guild_id, user_ids: ["123", "456"])
```

Handle the response:

```elixir
handle :guild_members_chunk, data do
  IO.puts("Received #{length(data.members)} members")
end
```

## Soundboard

### `request_soundboard_sounds(guild_ids)`

Request soundboard sounds for the given guild IDs. Responses arrive as `:soundboard_sounds` events.

```elixir
Lingo.request_soundboard_sounds(["guild_id_1", "guild_id_2"])
```

## Channel Info

### `request_channel_info(guild_id, fields \\ ["status", "voice_start_time"])`

Request ephemeral channel info for a guild. Responses arrive as `:channel_info` events.

```elixir
Lingo.request_channel_info(guild_id)
Lingo.request_channel_info(guild_id, ["status"])
```
