# API: Channels & Messages

All on the `Lingo` module. Return `{:ok, data}` or `{:error, reason}` unless noted.

## Channels

### get_channel

```elixir
Lingo.get_channel(channel_id)
```

### edit_channel

```elixir
Lingo.edit_channel(channel_id, params, opts \\ [])
```

Supports `reason`.

### delete_channel

```elixir
Lingo.delete_channel(channel_id, opts \\ [])
```

Supports `reason`.

### edit_channel_permissions

```elixir
Lingo.edit_channel_permissions(channel_id, overwrite_id, params, opts \\ [])
```

`params`: `%{allow: bitfield, deny: bitfield, type: 0|1}`. Supports `reason`.

### delete_channel_permissions

```elixir
Lingo.delete_channel_permissions(channel_id, overwrite_id, opts \\ [])
```

Supports `reason`.

### follow_channel

```elixir
Lingo.follow_channel(channel_id, webhook_channel_id, opts \\ [])
```

Follow an announcement channel. Supports `reason`.

### trigger_typing

```elixir
Lingo.trigger_typing(channel_id)
```

### list_channel_invites / create_invite

```elixir
Lingo.list_channel_invites(channel_id)
Lingo.create_invite(channel_id, params \\ %{}, opts \\ [])
```

`create_invite` params: `%{max_age: 86400, max_uses: 1, temporary: false}`. Supports `reason`.

## Messages

### get_message

```elixir
Lingo.get_message(channel_id, message_id)
```

### list_messages

```elixir
Lingo.list_messages(channel_id, opts \\ [])
```

Options: `limit` (1-100), `before`, `after`, `around` (snowflake IDs).

### send_message

```elixir
Lingo.send_message(channel_id, params)
```

`params` can be a string, keyword list, or map:

```elixir
Lingo.send_message(ch, "Hello!")
Lingo.send_message(ch, content: "Hello!", embeds: [embed])
Lingo.send_message(ch, %{content: "File:", files: [{"log.txt", data}]})
```

### edit_message

```elixir
Lingo.edit_message(channel_id, message_id, params)
```

Same param format as `send_message`. Supports file attachments.

### delete_message

```elixir
Lingo.delete_message(channel_id, message_id, opts \\ [])
```

Supports `reason`.

### bulk_delete_messages

```elixir
Lingo.bulk_delete_messages(channel_id, message_ids, opts \\ [])
```

Delete 2-100 messages (must be less than 14 days old). Handles chunking for you. Supports `reason`.

### crosspost_message

```elixir
Lingo.crosspost_message(channel_id, message_id)
```

### search_messages

```elixir
Lingo.search_messages(guild_id, opts \\ [])
```

Options: `content`, `author_id`, `mentions`, `has`, `min_id`, `max_id`, `channel_id`, `pinned`, `limit`, `offset`, `sort_by`, `sort_order`.

## Pins

### list_pins

```elixir
Lingo.list_pins(channel_id)
```

### pin_message / unpin_message

```elixir
Lingo.pin_message(channel_id, message_id, opts \\ [])
Lingo.unpin_message(channel_id, message_id, opts \\ [])
```

Both support `reason`.

## Reactions

### add_reaction

```elixir
Lingo.add_reaction(channel_id, message_id, emoji)
```

`emoji` is a string: `"thumbsup"` for unicode, `"name:id"` for custom.

### remove_own_reaction

```elixir
Lingo.remove_own_reaction(channel_id, message_id, emoji)
```

### remove_user_reaction

```elixir
Lingo.remove_user_reaction(channel_id, message_id, emoji, user_id)
```

### list_reactions

```elixir
Lingo.list_reactions(channel_id, message_id, emoji, opts \\ [])
```

Options: `after`, `limit` (1-100), `type`.

### remove_all_reactions

```elixir
Lingo.remove_all_reactions(channel_id, message_id)
```

### remove_emoji_reactions

```elixir
Lingo.remove_emoji_reactions(channel_id, message_id, emoji)
```

## Threads

### start_thread_from_message

```elixir
Lingo.start_thread_from_message(channel_id, message_id, params, opts \\ [])
```

`params`: `%{name: "Thread", auto_archive_duration: 1440}`. Supports `reason`.

### start_thread

```elixir
Lingo.start_thread(channel_id, params, opts \\ [])
```

Start a thread without a parent message. `params`: `%{name: "Thread", type: 11}`. Supports `reason`.

### join_thread / leave_thread

```elixir
Lingo.join_thread(channel_id)
Lingo.leave_thread(channel_id)
```

### add_thread_member / remove_thread_member

```elixir
Lingo.add_thread_member(channel_id, user_id)
Lingo.remove_thread_member(channel_id, user_id)
```

### get_thread_member

```elixir
Lingo.get_thread_member(channel_id, user_id, opts \\ [])
```

Options: `with_member`.

### list_thread_members

```elixir
Lingo.list_thread_members(channel_id, opts \\ [])
```

Options: `with_member`, `after`, `limit`.

### list_public_archived_threads / list_private_archived_threads

```elixir
Lingo.list_public_archived_threads(channel_id, opts \\ [])
Lingo.list_private_archived_threads(channel_id, opts \\ [])
```

Options: `before`, `limit`.

### list_joined_private_archived_threads

```elixir
Lingo.list_joined_private_archived_threads(channel_id, opts \\ [])
```

Options: `before`, `limit`.
