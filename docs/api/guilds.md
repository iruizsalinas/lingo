# API: Guilds, Members & Roles

All on the `Lingo` module. Return `{:ok, data}` or `{:error, reason}` unless noted.

## Guilds

### get_guild

```elixir
Lingo.get_guild(guild_id, opts \\ [])
```

Get a guild. Pass `with_counts: true` to include approximate member/presence counts.

### edit_guild

```elixir
Lingo.edit_guild(guild_id, params, opts \\ [])
```

Modify a guild. Supports `reason`.

### get_guild_preview

```elixir
Lingo.get_guild_preview(guild_id)
```

### list_channels

```elixir
Lingo.list_channels(guild_id)
```

### create_channel

```elixir
Lingo.create_channel(guild_id, params, opts \\ [])
```

Create a guild channel. `params`: `%{name: "general", type: 0}`. Supports `reason`.

### reorder_channels

```elixir
Lingo.reorder_channels(guild_id, positions)
```

`positions`: list of `%{id: channel_id, position: n}`.

### list_active_threads

```elixir
Lingo.list_active_threads(guild_id)
```

### list_guild_voice_regions

```elixir
Lingo.list_guild_voice_regions(guild_id)
```

### list_invites

```elixir
Lingo.list_invites(guild_id)
```

### list_integrations

```elixir
Lingo.list_integrations(guild_id)
```

### delete_integration

```elixir
Lingo.delete_integration(guild_id, integration_id, opts \\ [])
```

Supports `reason`.

### get_widget_settings / edit_widget / get_widget

```elixir
Lingo.get_widget_settings(guild_id)
Lingo.edit_widget(guild_id, params, opts \\ [])
Lingo.get_widget(guild_id)
```

`edit_widget` supports `reason`.

### get_widget_image

```elixir
Lingo.get_widget_image(guild_id, opts \\ [])
```

Pass `style:` to pick a widget style (`"shield"`, `"banner1"`, etc.).

### get_vanity_url

```elixir
Lingo.get_vanity_url(guild_id)
```

### get_welcome_screen / edit_welcome_screen

```elixir
Lingo.get_welcome_screen(guild_id)
Lingo.edit_welcome_screen(guild_id, params, opts \\ [])
```

`edit_welcome_screen` supports `reason`.

### get_onboarding / edit_onboarding

```elixir
Lingo.get_onboarding(guild_id)
Lingo.edit_onboarding(guild_id, params, opts \\ [])
```

`edit_onboarding` supports `reason`.

### get_prune_count / begin_prune

```elixir
Lingo.get_prune_count(guild_id, opts \\ [])
Lingo.begin_prune(guild_id, params \\ %{}, opts \\ [])
```

`get_prune_count` options: `days`, `include_roles`. `begin_prune` supports `reason`.

### search_messages

```elixir
Lingo.search_messages(guild_id, opts \\ [])
```

Options: `content`, `author_id`, `mentions`, `has`, `min_id`, `max_id`, `channel_id`, `pinned`, `limit`, `offset`, `sort_by`, `sort_order`.

### get_audit_log

```elixir
Lingo.get_audit_log(guild_id, opts \\ [])
```

Options: `user_id`, `action_type`, `before`, `after`, `limit`.

## Members

### get_member

```elixir
Lingo.get_member(guild_id, user_id)
```

### list_members

```elixir
Lingo.list_members(guild_id, opts \\ [])
```

Options: `limit` (1-1000), `after` (snowflake for pagination).

### search_members

```elixir
Lingo.search_members(guild_id, query, opts \\ [])
```

Search by username or nickname. Options: `limit` (1-1000).

### edit_member

```elixir
Lingo.edit_member(guild_id, user_id, params, opts \\ [])
```

`params`: `%{nick: "New Nick", roles: [role_ids], mute: false}`. Supports `reason`.

### edit_own_member

```elixir
Lingo.edit_own_member(guild_id, params, opts \\ [])
```

Modify the bot's own member. Supports `reason`.

### kick_member

```elixir
Lingo.kick_member(guild_id, user_id, opts \\ [])
```

Supports `reason`.

### add_member_role / remove_member_role

```elixir
Lingo.add_member_role(guild_id, user_id, role_id, opts \\ [])
Lingo.remove_member_role(guild_id, user_id, role_id, opts \\ [])
```

Both support `reason`.

## Bans

### list_bans

```elixir
Lingo.list_bans(guild_id, opts \\ [])
```

Options: `limit`, `before`, `after`.

### get_ban

```elixir
Lingo.get_ban(guild_id, user_id)
```

### ban_member

```elixir
Lingo.ban_member(guild_id, user_id, opts \\ [])
```

Options: `delete_message_seconds` (0-604800), `reason`.

### unban_member

```elixir
Lingo.unban_member(guild_id, user_id, opts \\ [])
```

Supports `reason`.

### bulk_ban

```elixir
Lingo.bulk_ban(guild_id, user_ids, opts \\ [])
```

Ban multiple users at once. Options: `delete_message_seconds`, `reason`.

## Roles

### list_roles

```elixir
Lingo.list_roles(guild_id)
```

### get_role

```elixir
Lingo.get_role(guild_id, role_id)
```

### create_role

```elixir
Lingo.create_role(guild_id, params, opts \\ [])
```

`params`: `%{name: "Mod", color: 0xFF0000, permissions: bitfield}`. Supports `reason`.

### edit_role

```elixir
Lingo.edit_role(guild_id, role_id, params, opts \\ [])
```

Supports `reason`.

### delete_role

```elixir
Lingo.delete_role(guild_id, role_id, opts \\ [])
```

Supports `reason`.

### reorder_roles

```elixir
Lingo.reorder_roles(guild_id, positions, opts \\ [])
```

`positions`: list of `%{id: role_id, position: n}`. Supports `reason`.

### get_role_member_counts

```elixir
Lingo.get_role_member_counts(guild_id)
```
