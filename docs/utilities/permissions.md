# Permissions

Permission bitfield helpers. Functions on the `Lingo` module delegate to `Lingo.Permissions`.

## Checking Permissions

### `has_permission?(bitfield, permission)`

Check if a bitfield includes a permission.

```elixir
Lingo.has_permission?(member.permissions, :manage_messages)
```

`bitfield` can be an integer or a string (Discord sends permissions as strings).

### `has_all_permissions?(bitfield, permissions)`

Check if a bitfield includes all of the listed permissions.

```elixir
Lingo.has_all_permissions?(perms, [:manage_messages, :manage_channels])
```

### `has_any_permission?(bitfield, permissions)`

Check if a bitfield includes at least one of the listed permissions.

### `permission_list(bitfield)`

Convert a bitfield to a list of permission atoms.

```elixir
Lingo.permission_list(member.permissions)
# [:send_messages, :view_channel, :read_message_history, ...]
```

### `resolve_permissions(permissions)`

Convert a list of permission atoms to a bitfield integer.

```elixir
Lingo.Permissions.resolve([:send_messages, :embed_links])
# 18432
```

## Computing Effective Permissions

### `compute_permissions(everyone_perms, role_ids, roles, overwrites \\ [], member_id \\ nil)`

Compute a member's effective permissions in a channel.

```elixir
guild = Lingo.cached_guild(guild_id)
member = Lingo.cached_member(guild_id, user_id)
channel = Lingo.cached_channel(channel_id)
roles = Lingo.cached_roles(guild_id)

everyone_role = Enum.find(roles, &(&1.id == guild_id))

perms = Lingo.compute_permissions(
  everyone_role.permissions,
  member.roles,
  roles,
  channel.permission_overwrites,
  user_id
)

if Lingo.has_permission?(perms, :send_messages) do
  # can send messages in this channel
end
```

The computation follows Discord's permission algorithm:
1. Start with the @everyone role permissions
2. OR in permissions from the member's roles
3. If the result includes `administrator`, return all permissions
4. Apply channel overwrites: @everyone overwrite, then role overwrites, then member overwrite

## All Permissions

| Permission | Bit |
|------------|-----|
| `:create_instant_invite` | 0 |
| `:kick_members` | 1 |
| `:ban_members` | 2 |
| `:administrator` | 3 |
| `:manage_channels` | 4 |
| `:manage_guild` | 5 |
| `:add_reactions` | 6 |
| `:view_audit_log` | 7 |
| `:priority_speaker` | 8 |
| `:stream` | 9 |
| `:view_channel` | 10 |
| `:send_messages` | 11 |
| `:send_tts_messages` | 12 |
| `:manage_messages` | 13 |
| `:embed_links` | 14 |
| `:attach_files` | 15 |
| `:read_message_history` | 16 |
| `:mention_everyone` | 17 |
| `:use_external_emojis` | 18 |
| `:view_guild_insights` | 19 |
| `:connect` | 20 |
| `:speak` | 21 |
| `:mute_members` | 22 |
| `:deafen_members` | 23 |
| `:move_members` | 24 |
| `:use_vad` | 25 |
| `:change_nickname` | 26 |
| `:manage_nicknames` | 27 |
| `:manage_roles` | 28 |
| `:manage_webhooks` | 29 |
| `:manage_guild_expressions` | 30 |
| `:use_application_commands` | 31 |
| `:request_to_speak` | 32 |
| `:manage_events` | 33 |
| `:manage_threads` | 34 |
| `:create_public_threads` | 35 |
| `:create_private_threads` | 36 |
| `:use_external_stickers` | 37 |
| `:send_messages_in_threads` | 38 |
| `:use_embedded_activities` | 39 |
| `:moderate_members` | 40 |
| `:view_creator_monetization_analytics` | 41 |
| `:use_soundboard` | 42 |
| `:create_guild_expressions` | 43 |
| `:create_events` | 44 |
| `:use_external_sounds` | 45 |
| `:send_voice_messages` | 46 |
| `:send_polls` | 49 |
| `:use_external_apps` | 50 |
| `:pin_messages` | 51 |
| `:bypass_slowmode` | 52 |

`Lingo.Permissions.all_permissions()` returns the full list of permission atoms.
