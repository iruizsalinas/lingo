# Types

All types are in the `Lingo.Type` namespace. Each has a `new/1` constructor that takes a map (typically from an API response) and returns a struct, or `nil` for `nil` input.

## Guild

`Lingo.Type.Guild`

| Field | Type |
|-------|------|
| `id` | snowflake |
| `name` | string |
| `icon` | string \| nil |
| `splash` | string \| nil |
| `discovery_splash` | string \| nil |
| `owner` | boolean |
| `owner_id` | snowflake |
| `permissions` | string |
| `afk_channel_id` | snowflake \| nil |
| `afk_timeout` | integer |
| `widget_enabled` | boolean |
| `widget_channel_id` | snowflake \| nil |
| `verification_level` | `:none \| :low \| :medium \| :high \| :very_high` |
| `default_message_notifications` | `:all_messages \| :only_mentions` |
| `explicit_content_filter` | `:disabled \| :members_without_roles \| :all_members` |
| `roles` | `[Role]` |
| `emojis` | `[Emoji]` |
| `features` | `[string]` |
| `mfa_level` | `:none \| :elevated` |
| `application_id` | snowflake \| nil |
| `system_channel_id` | snowflake \| nil |
| `system_channel_flags` | integer |
| `rules_channel_id` | snowflake \| nil |
| `max_presences` | integer \| nil |
| `max_members` | integer |
| `vanity_url_code` | string \| nil |
| `description` | string \| nil |
| `banner` | string \| nil |
| `premium_tier` | `:none \| :tier_1 \| :tier_2 \| :tier_3` |
| `premium_subscription_count` | integer |
| `preferred_locale` | string |
| `public_updates_channel_id` | snowflake \| nil |
| `nsfw_level` | `:default \| :explicit \| :safe \| :age_restricted` |
| `stickers` | `[Sticker]` |
| `channels` | `[Channel]` |
| `members` | `[Member]` |
| `member_count` | integer |
| `large` | boolean |
| `unavailable` | boolean |

## Channel

`Lingo.Type.Channel`

| Field | Type |
|-------|------|
| `id` | snowflake |
| `type` | see below |
| `guild_id` | snowflake \| nil |
| `position` | integer |
| `permission_overwrites` | `[Overwrite]` |
| `name` | string |
| `topic` | string \| nil |
| `nsfw` | boolean |
| `last_message_id` | snowflake \| nil |
| `bitrate` | integer |
| `user_limit` | integer |
| `rate_limit_per_user` | integer |
| `recipients` | list |
| `icon` | string \| nil |
| `owner_id` | snowflake \| nil |
| `parent_id` | snowflake \| nil |
| `last_pin_timestamp` | string \| nil |
| `rtc_region` | string \| nil |
| `video_quality_mode` | integer |
| `message_count` | integer |
| `member_count` | integer |
| `thread_metadata` | map \| nil |
| `flags` | integer |

Channel types: `:guild_text`, `:dm`, `:guild_voice`, `:group_dm`, `:guild_category`, `:guild_announcement`, `:announcement_thread`, `:public_thread`, `:private_thread`, `:guild_stage_voice`, `:guild_directory`, `:guild_forum`, `:guild_media`.

### Overwrite

`Lingo.Type.Overwrite`

| Field | Type |
|-------|------|
| `id` | snowflake |
| `type` | `:role \| :member` |
| `allow` | string (bitfield) |
| `deny` | string (bitfield) |

## User

`Lingo.Type.User`

| Field | Type |
|-------|------|
| `id` | snowflake |
| `username` | string |
| `discriminator` | string |
| `global_name` | string \| nil |
| `avatar` | string \| nil |
| `bot` | boolean |
| `system` | boolean |
| `mfa_enabled` | boolean |
| `banner` | string \| nil |
| `accent_color` | integer \| nil |
| `locale` | string \| nil |
| `flags` | integer |
| `premium_type` | integer |
| `public_flags` | integer |

## Member

`Lingo.Type.Member`

| Field | Type |
|-------|------|
| `user` | `User \| nil` |
| `nick` | string \| nil |
| `avatar` | string \| nil |
| `roles` | `[snowflake]` |
| `joined_at` | string |
| `premium_since` | string \| nil |
| `deaf` | boolean |
| `mute` | boolean |
| `flags` | integer |
| `pending` | boolean |
| `permissions` | string \| nil |
| `communication_disabled_until` | string \| nil |

## Message

`Lingo.Type.Message`

| Field | Type |
|-------|------|
| `id` | snowflake |
| `channel_id` | snowflake |
| `guild_id` | snowflake \| nil |
| `author` | `User \| nil` |
| `member` | `Member \| nil` |
| `content` | string |
| `timestamp` | string |
| `edited_timestamp` | string \| nil |
| `tts` | boolean |
| `mention_everyone` | boolean |
| `mentions` | list |
| `mention_roles` | `[snowflake]` |
| `attachments` | `[Attachment]` |
| `embeds` | list |
| `reactions` | `[Reaction]` |
| `pinned` | boolean |
| `webhook_id` | snowflake \| nil |
| `type` | integer |
| `flags` | integer |
| `referenced_message` | `Message \| nil` |
| `thread` | `Channel \| nil` |
| `components` | list |

### Attachment

`Lingo.Type.Attachment`

| Field | Type |
|-------|------|
| `id` | snowflake |
| `filename` | string |
| `description` | string \| nil |
| `content_type` | string \| nil |
| `size` | integer |
| `url` | string |
| `proxy_url` | string |
| `height` | integer \| nil |
| `width` | integer \| nil |

## Role

`Lingo.Type.Role`

| Field | Type |
|-------|------|
| `id` | snowflake |
| `name` | string |
| `color` | integer |
| `hoist` | boolean |
| `icon` | string \| nil |
| `unicode_emoji` | string \| nil |
| `position` | integer |
| `permissions` | string (bitfield) |
| `managed` | boolean |
| `mentionable` | boolean |
| `tags` | map \| nil |
| `flags` | integer |

## Emoji

`Lingo.Type.Emoji`

| Field | Type |
|-------|------|
| `id` | snowflake \| nil |
| `name` | string |
| `roles` | `[snowflake]` |
| `user` | `User \| nil` |
| `require_colons` | boolean |
| `managed` | boolean |
| `animated` | boolean |
| `available` | boolean |

`Lingo.Type.Emoji.format/1` returns the string representation: unicode char for standard, `<:name:id>` or `<a:name:id>` for custom.

## Interaction

`Lingo.Type.Interaction`

| Field | Type |
|-------|------|
| `id` | snowflake |
| `application_id` | snowflake |
| `type` | `:ping \| :application_command \| :message_component \| :autocomplete \| :modal_submit` |
| `data` | map |
| `guild_id` | snowflake \| nil |
| `channel` | map \| nil |
| `channel_id` | snowflake \| nil |
| `member` | `Member \| nil` |
| `user` | `User \| nil` |
| `token` | string |
| `message` | `Message \| nil` |
| `app_permissions` | string |
| `locale` | string |
| `guild_locale` | string \| nil |
| `entitlements` | list |

`Lingo.Type.Interaction.author/1` returns the user, preferring `member.user` and falling back to `user`.

## Other Types

### VoiceState

Fields: `guild_id`, `channel_id`, `user_id`, `member`, `session_id`, `deaf`, `mute`, `self_deaf`, `self_mute`, `self_stream`, `self_video`, `suppress`, `request_to_speak_timestamp`.

### Presence

Fields: `user`, `guild_id`, `status` (`:online | :idle | :dnd | :offline`), `activities`, `client_status`.

### Activity

Fields: `name`, `type` (`:playing | :streaming | :listening | :watching | :custom | :competing`), `url`, `created_at`, `application_id`, `details`, `state`.

### ReactionEvent

Fields: `user_id`, `channel_id`, `message_id`, `guild_id`, `emoji`, `member`, `message_author_id`, `burst`, `burst_colors`, `type`.

### Invite

Fields: `type`, `code`, `guild`, `channel`, `inviter`, `target_type`, `target_user`, `approximate_presence_count`, `approximate_member_count`, `expires_at`, `uses`, `max_uses`, `max_age`, `temporary`, `created_at`, `flags`.

### Ban

Fields: `reason`, `user`.

### Webhook

Fields: `id`, `type` (`:incoming | :channel_follower | :application`), `guild_id`, `channel_id`, `user`, `name`, `avatar`, `token`, `application_id`, `url`.

### Entitlement

Fields: `id`, `sku_id`, `application_id`, `user_id`, `guild_id`, `type`, `deleted`, `starts_at`, `ends_at`, `consumed`, `subscription_id`.

### ScheduledEvent

Fields: `id`, `guild_id`, `channel_id`, `creator_id`, `name`, `description`, `scheduled_start_time`, `scheduled_end_time`, `privacy_level`, `status`, `entity_type`, `entity_id`, `entity_metadata`, `creator`, `user_count`, `image`.

### StageInstance

Fields: `id`, `guild_id`, `channel_id`, `topic`, `privacy_level`, `guild_scheduled_event_id`.

### AutoModerationRule

Fields: `id`, `guild_id`, `name`, `creator_id`, `event_type`, `trigger_type`, `trigger_metadata`, `actions`, `enabled`, `exempt_roles`, `exempt_channels`.

### Sticker

Fields: `id`, `pack_id`, `name`, `description`, `tags`, `type`, `format_type`, `available`, `guild_id`, `user`, `sort_value`.

### GuildTemplate

Fields: `code`, `name`, `description`, `usage_count`, `creator_id`, `creator`, `created_at`, `updated_at`, `source_guild_id`, `serialized_source_guild`, `is_dirty`.

### ApplicationCommand

Fields: `id`, `type`, `application_id`, `guild_id`, `name`, `description`, `options`, `default_member_permissions`, `nsfw`, `version`, `integration_types`, `contexts`.

### CommandOption

Fields: `type`, `name`, `description`, `required`, `choices`, `options`, `channel_types`, `min_value`, `max_value`, `min_length`, `max_length`, `autocomplete`.

### Snowflake

`Lingo.Type.Snowflake.timestamp/1` converts a snowflake string to a `DateTime`. `Lingo.Type.Snowflake.from_timestamp/1` creates a snowflake from a `DateTime`.

### Embed

Fields: `title`, `type`, `description`, `url`, `timestamp`, `color`, `footer`, `image`, `thumbnail`, `video`, `provider`, `author`, `fields`.
