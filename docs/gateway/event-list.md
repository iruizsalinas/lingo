# Events

Gateway events and the data shape your `handle` block receives.

## Guilds

| Event | Data |
|-------|------|
| `:guild_create` | `Guild` struct (with `.channels`, `.members`, `.roles` populated) |
| `:guild_update` | `%{old: Guild \| nil, new: Guild}` |
| `:guild_delete` | `%{id: snowflake, unavailable: boolean}` or `%{old: Guild \| nil, new: %{id, unavailable}}` |
| `:guild_audit_log_entry_create` | `AuditLogEntry` struct |
| `:guild_integrations_update` | Raw map with `"guild_id"` |

## Channels

| Event | Data |
|-------|------|
| `:channel_create` | `Channel` struct |
| `:channel_update` | `%{old: Channel \| nil, new: Channel}` |
| `:channel_delete` | `%{old: Channel \| nil, new: Channel}` |
| `:channel_pins_update` | Raw map with `"channel_id"`, `"guild_id"`, `"last_pin_timestamp"` |

## Threads

| Event | Data |
|-------|------|
| `:thread_create` | `Channel` struct |
| `:thread_update` | `%{old: Channel \| nil, new: Channel}` |
| `:thread_delete` | `%{old: Channel \| nil, new: Channel}` |
| `:thread_list_sync` | `%{guild_id: str, channel_ids: list, threads: [Channel], members: list}` |
| `:thread_member_update` | Raw map |
| `:thread_members_update` | Raw map |

## Members

| Event | Data |
|-------|------|
| `:guild_member_add` | `Member` struct |
| `:guild_member_update` | `%{old: Member \| nil, new: Member}` |
| `:guild_member_remove` | `%{old: Member \| nil, new: %{guild_id: str, user: User}}` |
| `:guild_members_chunk` | `%{guild_id: str, members: [Member], chunk_index: int, chunk_count: int, not_found: list, nonce: str}` |

## Roles

| Event | Data |
|-------|------|
| `:guild_role_create` | `Role` struct |
| `:guild_role_update` | `%{old: Role \| nil, new: Role}` |
| `:guild_role_delete` | `%{old: Role \| nil, new: %{guild_id: str, role_id: str}}` |

## Emojis & Stickers

| Event | Data |
|-------|------|
| `:guild_emojis_update` | `%{old: %{guild_id, emojis: [Emoji]}, new: %{guild_id, emojis: [Emoji]}}` |
| `:guild_stickers_update` | `%{old: %{guild_id, stickers: [Sticker]}, new: %{guild_id, stickers: [Sticker]}}` |

## Bans

| Event | Data |
|-------|------|
| `:guild_ban_add` | `%{guild_id: str, user: User}` |
| `:guild_ban_remove` | `%{guild_id: str, user: User}` |

## Messages

| Event | Data |
|-------|------|
| `:message_create` | `Message` struct |
| `:message_update` | `%{old: Message \| nil, new: Message}` |
| `:message_delete` | `%{old: Message \| nil, new: %{id: str, channel_id: str, guild_id: str}}` |
| `:message_delete_bulk` | `%{ids: [str], channel_id: str, guild_id: str}` |

## Reactions

| Event | Data |
|-------|------|
| `:message_reaction_add` | `ReactionEvent` struct |
| `:message_reaction_remove` | `ReactionEvent` struct |
| `:message_reaction_remove_all` | `%{channel_id: str, message_id: str, guild_id: str}` |
| `:message_reaction_remove_emoji` | `ReactionEvent` struct |

## Polls

| Event | Data |
|-------|------|
| `:message_poll_vote_add` | Raw map |
| `:message_poll_vote_remove` | Raw map |

## Presence & Typing

| Event | Data |
|-------|------|
| `:presence_update` | `%{old: Presence \| nil, new: Presence}` |
| `:typing_start` | Raw map with `"channel_id"`, `"guild_id"`, `"user_id"`, `"timestamp"` |

## Voice

| Event | Data |
|-------|------|
| `:voice_state_update` | `%{old: VoiceState \| nil, new: VoiceState}` |
| `:voice_server_update` | Raw map with `"token"`, `"guild_id"`, `"endpoint"` |
| `:voice_channel_effect_send` | Raw map |

## Stage Instances

| Event | Data |
|-------|------|
| `:stage_instance_create` | `StageInstance` struct |
| `:stage_instance_update` | `StageInstance` struct |
| `:stage_instance_delete` | `StageInstance` struct |

## Invites

| Event | Data |
|-------|------|
| `:invite_create` | `Invite` struct |
| `:invite_delete` | `%{channel_id: str, guild_id: str, code: str}` |

## Scheduled Events

| Event | Data |
|-------|------|
| `:guild_scheduled_event_create` | `ScheduledEvent` struct |
| `:guild_scheduled_event_update` | `ScheduledEvent` struct |
| `:guild_scheduled_event_delete` | `ScheduledEvent` struct |
| `:guild_scheduled_event_user_add` | Raw map |
| `:guild_scheduled_event_user_remove` | Raw map |

## Auto Moderation

| Event | Data |
|-------|------|
| `:auto_moderation_rule_create` | `AutoModerationRule` struct |
| `:auto_moderation_rule_update` | `AutoModerationRule` struct |
| `:auto_moderation_rule_delete` | `AutoModerationRule` struct |
| `:auto_moderation_action_execution` | Raw map |

## Entitlements

| Event | Data |
|-------|------|
| `:entitlement_create` | `Entitlement` struct |
| `:entitlement_update` | `Entitlement` struct |
| `:entitlement_delete` | `Entitlement` struct |

## Soundboard

| Event | Data |
|-------|------|
| `:guild_soundboard_sound_create` | Raw map |
| `:guild_soundboard_sound_update` | Raw map |
| `:guild_soundboard_sound_delete` | Raw map |
| `:guild_soundboard_sounds_update` | Raw map |
| `:soundboard_sounds` | Raw map |

## Integrations

| Event | Data |
|-------|------|
| `:integration_create` | Raw map |
| `:integration_update` | Raw map |
| `:integration_delete` | Raw map |

## Subscriptions

| Event | Data |
|-------|------|
| `:subscription_create` | Raw map |
| `:subscription_update` | Raw map |
| `:subscription_delete` | Raw map |

## User

| Event | Data |
|-------|------|
| `:user_update` | `%{old: User \| nil, new: User}` |

## Webhooks

| Event | Data |
|-------|------|
| `:webhooks_update` | Raw map with `"guild_id"`, `"channel_id"` |

## Commands

| Event | Data |
|-------|------|
| `:application_command_permissions_update` | Raw map |

## Connection

| Event | Data |
|-------|------|
| `:ready` | `%{shard_count: integer}`, fires once when all shards are connected |

## Shard

| Event | Data |
|-------|------|
| `:shard_ready` | Raw map with `"user"`, `"guilds"`, `"session_id"`, `"shard_id"` |
| `:shard_resumed` | `%{shard_id: integer}` |
| `:shard_reconnecting` | `%{shard_id: integer}` |
| `:shard_disconnect` | `%{shard_id: integer, code: integer}` |
| `:shard_error` | `%{shard_id: integer, code: integer}` |

## Rate Limit

| Event | Data |
|-------|------|
| `:rate_limit` | `%{method: atom, path: string, retry_after: integer, global: boolean}` |
