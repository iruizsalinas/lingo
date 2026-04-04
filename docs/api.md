# REST API

Lingo wraps most of the Discord REST API as functions on the `Lingo` module. They work both inside and outside of command handlers.

## Making API Calls

```elixir
# Send a message
Lingo.send_message(channel_id, content: "Hello!")

# Send a message with an embed
Lingo.send_message(channel_id, %{
  content: "Check this out:",
  embeds: [Lingo.embed(title: "My Embed", description: "Some text", color: 0x00FF00)]
})

# Edit a message
Lingo.edit_message(channel_id, message_id, content: "Edited!")

# Delete a message
Lingo.delete_message(channel_id, message_id)
```

## Return Values

API functions return `{:ok, result}` or `{:error, reason}`:

```elixir
case Lingo.send_message(channel_id, content: "Hello!") do
  {:ok, message} -> IO.puts("Sent message #{message["id"]}")
  {:error, {status, body}} -> IO.puts("Failed: #{status}")
  {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
end
```

Some endpoints return `:ok` with no body (like deletes). Error tuples contain either `{status_code, response_body}` for HTTP errors or a raw reason for network failures.

## Audit Log Reasons

Many moderation endpoints accept a `reason:` option that shows up in the guild audit log:

```elixir
Lingo.ban_member(guild_id, user_id, reason: "Spamming")
Lingo.kick_member(guild_id, user_id, reason: "Inactive")
Lingo.delete_channel(channel_id, reason: "Cleanup")
Lingo.create_role(guild_id, %{name: "Muted"}, reason: "Auto-created mute role")
```

## Sending Files

Pass a `:files` key with a list of `{filename, binary_data}` tuples:

```elixir
Lingo.send_message(channel_id, %{
  content: "Here's a file:",
  files: [{"hello.txt", "Hello, world!"}]
})
```

Files work with `send_message`, `edit_message`, interaction responses, and webhook executions.

## Rate Limiting

Lingo handles rate limiting for you. If a request gets rate limited, it waits and retries automatically. Server errors also get retried with backoff.

You don't need to think about this, but you can listen for it:

```elixir
handle :rate_limit, info do
  Logger.warning("Rate limited: #{info.method} #{info.path} for #{info.retry_after}ms")
end
```

## Common Endpoints

Some frequently used functions. See the [API Reference](/api-guilds) for more.

### Messages

```elixir
Lingo.send_message(channel_id, content: "text")
Lingo.send_message(channel_id, %{embeds: [embed], components: [row]})
Lingo.edit_message(channel_id, message_id, content: "new text")
Lingo.delete_message(channel_id, message_id)
Lingo.list_messages(channel_id, limit: 10)
```

### Members

```elixir
Lingo.get_member(guild_id, user_id)
Lingo.edit_member(guild_id, user_id, %{nick: "New Nick"}, reason: "Requested")
Lingo.kick_member(guild_id, user_id, reason: "Inactive")
Lingo.add_member_role(guild_id, user_id, role_id, reason: "Auto role")
Lingo.remove_member_role(guild_id, user_id, role_id)
```

### Roles

```elixir
Lingo.create_role(guild_id, %{name: "Moderator", color: 0xFF0000, permissions: perms})
Lingo.edit_role(guild_id, role_id, %{name: "New Name"})
Lingo.delete_role(guild_id, role_id)
```

### Bans

```elixir
Lingo.ban_member(guild_id, user_id, delete_message_seconds: 86400, reason: "Spam")
Lingo.unban_member(guild_id, user_id, reason: "Appeal accepted")
Lingo.bulk_ban(guild_id, user_ids, delete_message_seconds: 86400)
```

### Reactions

```elixir
Lingo.add_reaction(channel_id, message_id, "thumbsup")
Lingo.add_reaction(channel_id, message_id, "custom_emoji:123456789")
Lingo.remove_all_reactions(channel_id, message_id)
```

### Threads

```elixir
Lingo.start_thread(channel_id, %{name: "Discussion", auto_archive_duration: 1440})
Lingo.start_thread_from_message(channel_id, message_id, %{name: "Thread"})
```
