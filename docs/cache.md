# Cache

Lingo keeps a local cache that updates automatically from gateway events. Fast lookups, no API calls needed.

## Configuration

To disable caching entirely, pass `false`:

```elixir
{Lingo, bot: MyBot.Bot, token: token, intents: intents, cache: false}
```

To only cache specific resources:

```elixir
{Lingo,
 bot: MyBot.Bot,
 token: token,
 intents: [:guilds, :guild_messages],
 cache: [
   enabled: [:guilds, :channels, :users, :members, :roles],
   max_messages_per_channel: 500
 ]}
```

**`enabled`**: which resources to cache. Defaults to all of them (`:guilds`, `:channels`, `:users`, `:members`, `:presences`, `:roles`, `:voice_states`, `:messages`). Resources you leave out won't be stored and their `cached_*` functions return `nil`. Events still fire regardless.

**`max_messages_per_channel`**: how many messages to keep per channel before dropping the oldest. Defaults to `200`.

## Functions

### cached_guild

```elixir
Lingo.cached_guild(guild_id)
```

Returns a `Guild` struct or `nil`. The cached guild has empty `.channels`, `.members`, and `.roles` since those live in their own cache slots. Use `cached_roles/1` etc. to get them.

### cached_guilds

```elixir
Lingo.cached_guilds()
```

All cached guilds as a list.

### cached_channel

```elixir
Lingo.cached_channel(channel_id)
```

Returns a `Channel` struct or `nil`. Threads are stored here too.

### cached_user

```elixir
Lingo.cached_user(user_id)
```

Returns a `User` struct or `nil`.

### cached_me

```elixir
Lingo.cached_me()
```

The bot's own user. Set when the bot connects.

### cached_member

```elixir
Lingo.cached_member(guild_id, user_id)
```

Returns a `Member` struct (with `.user` populated) or `nil`.

### cached_role

```elixir
Lingo.cached_role(guild_id, role_id)
```

Returns a `Role` struct or `nil`.

### cached_roles

```elixir
Lingo.cached_roles(guild_id)
```

All roles for a guild as a list.

### cached_message

```elixir
Lingo.cached_message(channel_id, message_id)
```

Returns a `Message` struct or `nil`.

### cached_voice_state

```elixir
Lingo.cached_voice_state(guild_id, user_id)
```

Returns a `VoiceState` struct or `nil`. Cleared when the user leaves voice.

### cached_presence

```elixir
Lingo.cached_presence(guild_id, user_id)
```

Returns a `Presence` struct or `nil`.

## What Gets Cached

| Resource | Populated from |
|----------|---------------|
| Guilds | `guild_create`, `guild_update`, `guild_delete` |
| Channels | `guild_create`, `channel_create`, `channel_update`, `channel_delete` |
| Users | member/message events, `user_update` |
| Members | `guild_create`, `guild_member_add`, `guild_member_update`, `guild_member_remove` |
| Roles | `guild_create`, `guild_role_create`, `guild_role_update`, `guild_role_delete` |
| Messages | `message_create`, `message_update`, `message_delete` |
| Voice States | `guild_create`, `voice_state_update` |
| Presences | `guild_create`, `presence_update` |

When a guild gets deleted, everything related to it is cleaned up: channels, members, roles, presences, voice states, and messages.

## Cache vs API

Use the **cache** when you need data you know is there, speed matters, or slightly stale data is fine.

Use the **API** when you need guaranteed-fresh data, the entity might not be cached, or you need something that's never cached (audit logs, invites, etc.).
