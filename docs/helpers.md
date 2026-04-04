# Helpers

Cache-aware convenience functions for common checks. All on the `Lingo` module, backed by `Lingo.Helpers`.

These functions work entirely from cache data. If the relevant entities aren't cached, they return `false` (or `0` / `nil` where noted).

## Roles

### `role_editable?(guild_id, role_id)`

Whether the bot can edit this role. Returns `false` if:
- The role or guild isn't cached
- The role is managed by an integration
- The role is the @everyone role (`role_id == guild_id`)
- The bot lacks `:manage_roles`
- The bot's highest role is at or below this role in the hierarchy

Returns `true` if the bot owns the guild (bypasses hierarchy check).

```elixir
if Lingo.role_editable?(guild_id, role_id) do
  Lingo.edit_role(guild_id, role_id, %{name: "New Name"})
end
```

### `compare_role_positions(guild_id, role_id_a, role_id_b)`

Compare two roles by position. Returns `:gt`, `:lt`, `:eq`, or `nil` if either role isn't cached. Breaks ties by ID.

```elixir
case Lingo.compare_role_positions(guild_id, role_a, role_b) do
  :gt -> "Role A is higher"
  :lt -> "Role B is higher"
  :eq -> "Same position"
  nil -> "Couldn't compare"
end
```

## Members

### `member_manageable?(guild_id, user_id)`

Whether the bot's highest role is above the target member's highest role. Returns `false` if:
- The guild isn't cached
- The target is the bot itself
- The target is the guild owner
- The bot's highest role isn't above the target's

Returns `true` if the bot owns the guild.

### `member_kickable?(guild_id, user_id)`

`member_manageable?/2` **and** the bot has `:kick_members`.

```elixir
if Lingo.member_kickable?(guild_id, user_id) do
  Lingo.kick_member(guild_id, user_id, reason: "Bye")
end
```

### `member_bannable?(guild_id, user_id)`

`member_manageable?/2` **and** the bot has `:ban_members`.

### `member_permissions(guild_id, user_id)`

Compute a member's guild-level permissions as an integer bitfield. Returns all permissions if the user is the guild owner. Returns `0` if the member or guild isn't cached.

```elixir
perms = Lingo.member_permissions(guild_id, user_id)
Lingo.has_permission?(perms, :manage_messages)
```

### `member_display_name(guild_id, user_id)`

Get a member's display name. Checks in order: nick, global_name, username. Returns `nil` if the member isn't cached.

```elixir
name = Lingo.member_display_name(guild_id, user_id)
```

### `member_display_color(guild_id, user_id)`

Get the color of a member's highest colored role. Returns `0` (no color) if the member isn't cached or has no colored roles.

```elixir
color = Lingo.member_display_color(guild_id, user_id)
# e.g. 0xFF0000 for red
```

## Channels

### `permissions_for(channel_id, user_id)`

Compute a user's effective permissions in a specific channel, including overwrites. Returns `0` for DM channels or if the data isn't cached.

```elixir
perms = Lingo.permissions_for(channel_id, user_id)
Lingo.has_permission?(perms, :send_messages)
```

### `channel_viewable?(channel_id)`

Whether the bot has `:view_channel` in this channel.

### `channel_manageable?(channel_id)`

Whether the bot has both `:view_channel` and `:manage_channels` in this channel.

## Messages

### `message_deletable?(channel_id, message_id)`

Whether the bot can delete this message. True if the bot authored the message, or if the bot has `:manage_messages` in the channel. Returns `false` if the message isn't cached.

### `message_url(guild_id, channel_id, message_id)`

Build a message jump link.

```elixir
Lingo.message_url(guild_id, channel_id, message_id)
# "https://discord.com/channels/123/456/789"
```

## Collectors

Wait for interactions or reactions inline, without separate handler macros. See the [Interactions guide](/interactions#collectors) for usage examples.

### await_component

```elixir
Lingo.await_component(message_id, opts \\ [])
```

Block until a component interaction (button click, select menu) arrives on the given message. Returns `{:ok, interaction}` or `:timeout`.

The matched interaction is consumed and won't reach your `component` handlers.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `filter` | function | matches all | `fn interaction -> bool end` |
| `timeout` | integer | `60_000` | Milliseconds to wait |

### await_reaction

```elixir
Lingo.await_reaction(channel_id, message_id, opts \\ [])
```

Block until a reaction is added to the message. Returns `{:ok, reaction}` or `:timeout`.

The reaction is **not** consumed, so your `handle :message_reaction_add` still fires.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `filter` | function | matches all | `fn reaction -> bool end` |
| `timeout` | integer | `60_000` | Milliseconds to wait |

### collect_reactions

```elixir
Lingo.collect_reactions(channel_id, message_id, opts)
```

Collect all matching reactions during a time window. Returns `{:ok, [reaction_events]}`.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `filter` | function | matches all | `fn reaction -> bool end` |
| `timeout` | integer | **required** | Milliseconds to collect for |

## Formatting

### `timestamp(datetime, style \\ :short_datetime)`

Format a DateTime or unix timestamp for Discord's rendered timestamps. Discord displays these in the user's local timezone.

```elixir
Lingo.timestamp(DateTime.utc_now())                # short date/time (default)
Lingo.timestamp(DateTime.utc_now(), :relative)      # "just now", "2 hours ago"
Lingo.timestamp(DateTime.utc_now(), :long_date)     # "4 April 2026"
Lingo.timestamp(DateTime.utc_now(), :short_time)    # "16:20"
Lingo.timestamp(DateTime.utc_now(), :long_time)     # "16:20:30"
Lingo.timestamp(DateTime.utc_now(), :short_date)    # "04/04/2026"
Lingo.timestamp(DateTime.utc_now(), :long_datetime) # "Friday, 4 April 2026 16:20"
```

Also accepts a unix timestamp as an integer:

```elixir
Lingo.timestamp(1_712_246_400, :relative)
```

### `mention_user(id)`

```elixir
Lingo.mention_user(user_id)  # <@123456789>
```

### `mention_channel(id)`

```elixir
Lingo.mention_channel(channel_id)  # <#123456789>
```

### `mention_role(id)`

```elixir
Lingo.mention_role(role_id)  # <@&123456789>
```
