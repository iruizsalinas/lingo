# Intents

Intents control which gateway events your bot receives. Pass them as a list when starting Lingo:

```elixir
{Lingo,
 bot: MyBot.Bot,
 token: token,
 intents: [:guilds, :guild_messages, :message_content]}
```

## All Intents

| Intent | Bit | Events |
|--------|-----|--------|
| `:guilds` | 0 | `guild_create`, `guild_update`, `guild_delete`, `channel_create`, `channel_update`, `channel_delete`, `channel_pins_update`, `thread_create`, `thread_update`, `thread_delete`, `thread_list_sync`, `thread_member_update`, `thread_members_update`, `stage_instance_create`, `stage_instance_update`, `stage_instance_delete` |
| `:guild_members` | 1 | `guild_member_add`, `guild_member_update`, `guild_member_remove` |
| `:guild_moderation` | 2 | `guild_audit_log_entry_create`, `guild_ban_add`, `guild_ban_remove` |
| `:guild_expressions` | 3 | `guild_emojis_update`, `guild_stickers_update`, `guild_soundboard_sound_create`, `guild_soundboard_sound_update`, `guild_soundboard_sound_delete`, `guild_soundboard_sounds_update` |
| `:guild_integrations` | 4 | `guild_integrations_update`, `integration_create`, `integration_update`, `integration_delete` |
| `:guild_webhooks` | 5 | `webhooks_update` |
| `:guild_invites` | 6 | `invite_create`, `invite_delete` |
| `:guild_voice_states` | 7 | `voice_state_update` |
| `:guild_presences` | 8 | `presence_update` |
| `:guild_messages` | 9 | `message_create`, `message_update`, `message_delete`, `message_delete_bulk` |
| `:guild_message_reactions` | 10 | `message_reaction_add`, `message_reaction_remove`, `message_reaction_remove_all`, `message_reaction_remove_emoji` |
| `:guild_message_typing` | 11 | `typing_start` |
| `:direct_messages` | 12 | `message_create`, `message_update`, `message_delete`, `channel_pins_update` (in DMs) |
| `:direct_message_reactions` | 13 | `message_reaction_add`, `message_reaction_remove`, `message_reaction_remove_all`, `message_reaction_remove_emoji` (in DMs) |
| `:direct_message_typing` | 14 | `typing_start` (in DMs) |
| `:message_content` | 15 | Populates `content`, `embeds`, `attachments`, `components`, `poll` fields on message events |
| `:guild_scheduled_events` | 16 | `guild_scheduled_event_create`, `guild_scheduled_event_update`, `guild_scheduled_event_delete`, `guild_scheduled_event_user_add`, `guild_scheduled_event_user_remove` |
| `:auto_moderation_configuration` | 20 | `auto_moderation_rule_create`, `auto_moderation_rule_update`, `auto_moderation_rule_delete` |
| `:auto_moderation_execution` | 21 | `auto_moderation_action_execution` |
| `:guild_message_polls` | 24 | `message_poll_vote_add`, `message_poll_vote_remove` |
| `:direct_message_polls` | 25 | `message_poll_vote_add`, `message_poll_vote_remove` (in DMs) |

## Privileged Intents

Three intents are privileged and need extra setup in the application settings:

- **`:guild_members`**: needed for member add/update/remove events
- **`:guild_presences`**: needed for presence updates
- **`:message_content`**: needed to see message content in guild messages

Without `:message_content`, `message_create` events still fire but `content`, `embeds`, `attachments`, and `components` will be empty for messages the bot didn't send and that don't mention it.

## Raw Integer

You can pass a bitfield integer instead of a list:

```elixir
{Lingo, bot: MyBot.Bot, token: token, intents: 3276799}
```

## Helper Functions

On `Lingo.Gateway.Intents` (not re-exported on `Lingo`):

| Function | Description |
|----------|-------------|
| `Lingo.Gateway.Intents.resolve(list)` | Convert a list of atoms to a bitfield |
| `Lingo.Gateway.Intents.all()` | Bitfield with everything enabled |
| `Lingo.Gateway.Intents.non_privileged()` | Bitfield with only non-privileged intents |
| `Lingo.Gateway.Intents.privileged?(intent)` | Check if an intent is privileged |
| `Lingo.Gateway.Intents.names()` | List all intent atom names |
