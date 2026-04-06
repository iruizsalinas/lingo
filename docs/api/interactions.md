# API: Interactions & Commands

All on the `Lingo` module. Return `{:ok, data}` or `{:error, reason}` unless noted.

## Interaction Responses

Most of the time you'll use the [context helpers](/commands/context) (`reply!`, `defer!`, `update!`, `show_modal!`). These are the lower-level functions underneath them.

### create_interaction_response

```elixir
Lingo.create_interaction_response(interaction_id, token, type, data \\ nil)
```

`type` is one of: `:pong`, `:channel_message`, `:deferred_channel_message`, `:deferred_update_message`, `:update_message`, `:autocomplete`, `:modal`.

### get_original_response

```elixir
Lingo.get_original_response(token)
```

### edit_original_response

```elixir
Lingo.edit_original_response(token, params)
```

Supports file attachments.

### delete_original_response

```elixir
Lingo.delete_original_response(token)
```

### create_followup

```elixir
Lingo.create_followup(token, params)
```

Supports file attachments.

### get_followup / edit_followup / delete_followup

```elixir
Lingo.get_followup(token, message_id)
Lingo.edit_followup(token, message_id, params)
Lingo.delete_followup(token, message_id)
```

`edit_followup` supports file attachments.

## Command Registration

### register_commands

```elixir
Lingo.register_commands(MyBot.Bot)
```

Push all commands from a bot module as global commands. Uses bulk overwrite, so it replaces everything each time. Global commands can take up to an hour to show up.

### register_commands_to_guild

```elixir
Lingo.register_commands_to_guild(MyBot.Bot, "123456789")
```

Push all commands to a specific guild. Updates instantly, so it's good for development.

## Low-Level Command Management

These hit the API directly, bypassing your bot module's command definitions.

### Global Commands

```elixir
Lingo.list_global_commands()
Lingo.get_global_command(command_id)
Lingo.create_global_command(params)
Lingo.edit_global_command(command_id, params)
Lingo.delete_global_command(command_id)
Lingo.sync_global_commands(commands)
```

### Guild Commands

```elixir
Lingo.list_guild_commands(guild_id)
Lingo.get_guild_command(guild_id, command_id)
Lingo.create_guild_command(guild_id, params)
Lingo.edit_guild_command(guild_id, command_id, params)
Lingo.delete_guild_command(guild_id, command_id)
Lingo.sync_guild_commands(guild_id, commands)
```

### Command Permissions

```elixir
Lingo.list_command_permissions(guild_id)
Lingo.get_command_permissions(guild_id, command_id)
```
