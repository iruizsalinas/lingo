# API: Other Resources

All on the `Lingo` module. Return `{:ok, data}` or `{:error, reason}` unless noted.

## Users

### get_me / edit_me

```elixir
Lingo.get_me()
Lingo.edit_me(params)
```

### get_user

```elixir
Lingo.get_user(user_id)
```

### list_guilds

```elixir
Lingo.list_guilds(opts \\ [])
```

List the bot's guilds. Options: `before`, `after`, `limit`, `with_counts`.

### leave_guild

```elixir
Lingo.leave_guild(guild_id)
```

### create_dm

```elixir
Lingo.create_dm(user_id)
```

## Webhooks

### create_webhook

```elixir
Lingo.create_webhook(channel_id, params, opts \\ [])
```

Supports `reason`.

### list_channel_webhooks / list_guild_webhooks

```elixir
Lingo.list_channel_webhooks(channel_id)
Lingo.list_guild_webhooks(guild_id)
```

### get_webhook / get_webhook_with_token

```elixir
Lingo.get_webhook(webhook_id)
Lingo.get_webhook_with_token(webhook_id, token)
```

### edit_webhook / edit_webhook_with_token

```elixir
Lingo.edit_webhook(webhook_id, params, opts \\ [])
Lingo.edit_webhook_with_token(webhook_id, token, params)
```

`edit_webhook` supports `reason`.

### delete_webhook / delete_webhook_with_token

```elixir
Lingo.delete_webhook(webhook_id, opts \\ [])
Lingo.delete_webhook_with_token(webhook_id, token)
```

`delete_webhook` supports `reason`.

### execute_webhook

```elixir
Lingo.execute_webhook(webhook_id, token, params, opts \\ [])
```

Options: `wait` (return the message), `thread_id`. Supports file attachments.

### execute_slack_webhook / execute_github_webhook

```elixir
Lingo.execute_slack_webhook(webhook_id, token, params, opts \\ [])
Lingo.execute_github_webhook(webhook_id, token, params, opts \\ [])
```

Options: `wait`, `thread_id`.

### get_webhook_message / edit_webhook_message / delete_webhook_message

```elixir
Lingo.get_webhook_message(webhook_id, token, message_id, opts \\ [])
Lingo.edit_webhook_message(webhook_id, token, message_id, params, opts \\ [])
Lingo.delete_webhook_message(webhook_id, token, message_id, opts \\ [])
```

All accept `thread_id`. `edit_webhook_message` supports file attachments.

## Emojis

### Guild Emojis

```elixir
Lingo.list_emojis(guild_id)
Lingo.get_emoji(guild_id, emoji_id)
Lingo.create_emoji(guild_id, params, opts \\ [])
Lingo.edit_emoji(guild_id, emoji_id, params, opts \\ [])
Lingo.delete_emoji(guild_id, emoji_id, opts \\ [])
```

`create`, `edit`, and `delete` support `reason`.

### Application Emojis

```elixir
Lingo.list_app_emojis()
Lingo.get_app_emoji(emoji_id)
Lingo.create_app_emoji(params)
Lingo.edit_app_emoji(emoji_id, params)
Lingo.delete_app_emoji(emoji_id)
```

## Stickers

```elixir
Lingo.get_sticker(sticker_id)
Lingo.list_sticker_packs()
Lingo.get_sticker_pack(pack_id)
Lingo.list_guild_stickers(guild_id)
Lingo.get_guild_sticker(guild_id, sticker_id)
Lingo.create_guild_sticker(guild_id, params, opts \\ [])
Lingo.edit_guild_sticker(guild_id, sticker_id, params, opts \\ [])
Lingo.delete_guild_sticker(guild_id, sticker_id, opts \\ [])
```

Guild sticker `create`, `edit`, and `delete` support `reason`. `create_guild_sticker` uses multipart upload.

## Invites

### get_invite

```elixir
Lingo.get_invite(code, opts \\ [])
```

Options: `with_counts`, `with_expiration`, `guild_scheduled_event_id`.

### delete_invite

```elixir
Lingo.delete_invite(code, opts \\ [])
```

Supports `reason`.

### get_invite_target_users / set_invite_target_users / get_invite_target_users_status

```elixir
Lingo.get_invite_target_users(code)
Lingo.set_invite_target_users(code, user_ids)
Lingo.get_invite_target_users_status(code)
```

## Scheduled Events

```elixir
Lingo.list_scheduled_events(guild_id, opts \\ [])
Lingo.get_scheduled_event(guild_id, event_id, opts \\ [])
Lingo.create_scheduled_event(guild_id, params, opts \\ [])
Lingo.edit_scheduled_event(guild_id, event_id, params, opts \\ [])
Lingo.delete_scheduled_event(guild_id, event_id)
Lingo.list_scheduled_event_users(guild_id, event_id, opts \\ [])
```

`list` and `get` accept `with_user_count`. `create` and `edit` support `reason`. `list_scheduled_event_users` accepts `limit`, `with_member`, `before`, `after`.

## Stage Instances

```elixir
Lingo.create_stage(params, opts \\ [])
Lingo.get_stage(channel_id)
Lingo.edit_stage(channel_id, params, opts \\ [])
Lingo.delete_stage(channel_id, opts \\ [])
```

`create`, `edit`, and `delete` support `reason`.

## Auto Moderation

```elixir
Lingo.list_automod_rules(guild_id)
Lingo.get_automod_rule(guild_id, rule_id)
Lingo.create_automod_rule(guild_id, params, opts \\ [])
Lingo.edit_automod_rule(guild_id, rule_id, params, opts \\ [])
Lingo.delete_automod_rule(guild_id, rule_id, opts \\ [])
```

`create`, `edit`, and `delete` support `reason`.

## Templates

```elixir
Lingo.get_guild_template(code)
Lingo.list_guild_templates(guild_id)
Lingo.create_guild_template(guild_id, params)
Lingo.sync_guild_template(guild_id, code)
Lingo.edit_guild_template(guild_id, code, params)
Lingo.delete_guild_template(guild_id, code)
```

## Entitlements

```elixir
Lingo.list_entitlements(opts \\ [])
Lingo.get_entitlement(entitlement_id)
Lingo.consume_entitlement(entitlement_id)
Lingo.create_test_entitlement(params)
Lingo.delete_test_entitlement(entitlement_id)
```

`list_entitlements` options: `user_id`, `sku_ids`, `before`, `after`, `limit`, `guild_id`, `exclude_ended`, `exclude_deleted`.

## Application

```elixir
Lingo.get_application()
Lingo.edit_application(params)
Lingo.get_role_connection_metadata()
Lingo.edit_role_connection_metadata(params)
```

## Polls

```elixir
Lingo.list_poll_voters(channel_id, message_id, answer_id, opts \\ [])
Lingo.expire_poll(channel_id, message_id)
```

`list_poll_voters` options: `after`, `limit`.

## Voice

```elixir
Lingo.list_voice_regions()
Lingo.get_own_voice_state(guild_id)
Lingo.get_voice_state(guild_id, user_id)
Lingo.edit_own_voice_state(guild_id, params)
Lingo.edit_voice_state(guild_id, user_id, params)
```

## Soundboard

```elixir
Lingo.send_sound(channel_id, params)
Lingo.list_default_sounds()
Lingo.list_guild_sounds(guild_id)
Lingo.get_guild_sound(guild_id, sound_id)
Lingo.create_guild_sound(guild_id, params, opts \\ [])
Lingo.edit_guild_sound(guild_id, sound_id, params, opts \\ [])
Lingo.delete_guild_sound(guild_id, sound_id, opts \\ [])
```

Guild sound `create`, `edit`, and `delete` support `reason`.

## SKUs

```elixir
Lingo.list_skus()
Lingo.list_subscriptions(sku_id, opts \\ [])
Lingo.get_subscription(sku_id, subscription_id)
```

`list_subscriptions` options: `before`, `after`, `limit`, `user_id`.

