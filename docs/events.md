# Events

Use the `handle` macro to listen to gateway events.

## Basic Handler

```elixir
defmodule MyBot.Bot do
  use Lingo.Bot

  handle :message_create, msg do
    if msg.content == "hello" do
      Lingo.send_message(msg.channel_id, content: "Hello back!")
    end
  end
end
```

The first argument is the event name (an atom), the second is the variable that binds the event data. Data is already parsed into structs where applicable.

## Event Data Shapes

Most events give you either a struct or a map with `:old` and `:new` keys.

**Create events** hand you the struct directly:

```elixir
handle :guild_member_add, member do
  # member is a Lingo.Type.Member struct
  Lingo.send_message("welcome-channel-id",
    content: "Welcome, #{member.user.username}!"
  )
end
```

**Update events** give you `%{old: old_value, new: new_value}`:

```elixir
handle :guild_member_update, data do
  old_nick = data.old && data.old.nick
  new_nick = data.new.nick

  if old_nick != new_nick do
    Lingo.send_message("log-channel-id",
      content: "Nickname changed: #{old_nick} -> #{new_nick}"
    )
  end
end
```

`old` can be `nil` if the entity wasn't in the cache before.

**Delete events** also use `%{old: ..., new: ...}` where `new` has the minimal data from the event (usually just IDs):

```elixir
handle :message_delete, data do
  if data.old do
    Lingo.send_message("log-channel-id",
      content: "Deleted message by #{data.old.author.username}: #{data.old.content}"
    )
  end
end
```

See the [Events Reference](/event-list) for the exact data shape of every event.

## Common Patterns

### Ignoring Bot Messages

```elixir
handle :message_create, msg do
  unless msg.author && msg.author.bot do
    # process message
  end
end
```

### Logging Member Joins/Leaves

```elixir
handle :guild_member_add, member do
  Lingo.send_message("log-channel-id",
    content: "<@#{member.user.id}> joined the server."
  )
end

handle :guild_member_remove, data do
  user = data.new.user
  Lingo.send_message("log-channel-id",
    content: "#{user.username} left the server."
  )
end
```

### Role Changes

```elixir
handle :guild_role_create, role do
  Lingo.send_message("log-channel-id",
    content: "New role created: #{role.name}"
  )
end

handle :guild_role_delete, data do
  name = if data.old, do: data.old.name, else: data.new.role_id
  Lingo.send_message("log-channel-id",
    content: "Role deleted: #{name}"
  )
end
```

### Reactions

```elixir
handle :message_reaction_add, reaction do
  emoji_name = reaction.emoji.name
  Lingo.send_message(reaction.channel_id,
    content: "<@#{reaction.user_id}> reacted with #{emoji_name}"
  )
end
```

## Intents

You only receive events for the intents you've enabled. If a handler never fires, make sure the right intent is in your `intents` list:

```elixir
{Lingo,
 bot: MyBot.Bot,
 token: token,
 intents: [:guilds, :guild_members, :guild_messages, :message_content]}
```

See the [Intents Reference](/intents) for which intent gates which events.

Three intents are **privileged** and require extra setup: `:guild_members`, `:guild_presences`, and `:message_content`.

## The `ready` Event

`:ready` fires when the bot connects to the gateway. The data is a raw map with `"user"`, `"guilds"`, `"session_id"`, and an injected `"shard_id"` key:

```elixir
handle :ready, data do
  IO.puts("Shard #{data["shard_id"]} ready!")
end
```

## Internal Events

Lingo dispatches a few extra events that don't come from the gateway:

| Event | Data | When |
|-------|------|------|
| `:shard_reconnecting` | `%{shard_id: id}` | A shard is about to reconnect |
| `:shard_disconnect` | `%{shard_id: id, code: code}` | A shard disconnected (recoverable) |
| `:shard_error` | `%{shard_id: id, code: code}` | A shard got a fatal close code |
| `:rate_limit` | `%{method: m, path: p, retry_after: ms, global: bool}` | The API returned a 429 |

Handle them the same way:

```elixir
handle :rate_limit, info do
  if info.global do
    IO.puts("Global rate limit hit for #{info.retry_after}ms")
  end
end
```
