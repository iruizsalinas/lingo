# Commands

Slash commands are defined with the `command` macro inside a module that uses `Lingo.Bot`.

## Basic Command

```elixir
command "hello", "Says hello" do
  reply!(ctx, "Hello, #{ctx.user.username}!")
end
```

The first argument is the command name, the second is the description shown in the command picker. The block receives `ctx`, a `Lingo.Command.Context` struct with the interaction data.

## Options

Add options with the `options:` keyword. Use the [option builder functions](/commands/option-builders) to define each one:

```elixir
command "ban", "Ban a user",
  options: [
    user("target", "The user to ban", required: true),
    string("reason", "Reason for the ban"),
    integer("days", "Days of messages to delete", min_value: 0, max_value: 7)
  ] do
  target_id = option(ctx, :target)
  reason = option(ctx, :reason) || "No reason provided"
  days = option(ctx, :days) || 0

  Lingo.ban_member(ctx.guild_id, target_id, delete_message_seconds: days * 86400, reason: reason)
  reply!(ctx, "Banned <@#{target_id}>.")
end
```

`option(ctx, :name)` retrieves the value of an option by name. For `user`, `role`, `channel`, and `mentionable` types, the value is a snowflake ID. Use the `get_*` shortcuts to resolve the full object, see [Context: Resolved Data](/commands/context#resolved-data) for details.

See [Option Builders](/commands/option-builders) for the full list of builder functions, keyword options, and choices format.

## Subcommands

Use `subcommand/3` and `subcommand_group/3` to nest commands:

```elixir
command "config", "Server configuration",
  options: [
    subcommand_group("roles", "Role settings",
      options: [
        subcommand("autorole", "Set the auto-assign role",
          options: [role("role", "The role", required: true)]
        ),
        subcommand("sticky", "Set a sticky role",
          options: [role("role", "The role", required: true)]
        )
      ]
    ),
    subcommand("reset", "Reset all config")
  ] do
  case option(ctx, :roles) do
    %{autorole: opts} ->
      reply!(ctx, "Auto role set to <@&#{opts[:role]}>")

    %{sticky: opts} ->
      reply!(ctx, "Sticky role set to <@&#{opts[:role]}>")

    nil ->
      case option(ctx, :reset) do
        %{} -> reply!(ctx, "Config reset.")
        nil -> reply!(ctx, "Unknown subcommand.")
      end
  end
end
```

Subcommand options come back as nested maps. `option(ctx, :roles)` returns something like `%{autorole: %{role: "123"}}` when the user runs `/config roles autorole`.

## Permissions

Restrict who can use a command by default with a permission bitfield:

```elixir
command "kick", "Kick a member",
  default_member_permissions: Lingo.Permissions.resolve([:kick_members]),
  options: [
    user("target", "The member to kick", required: true)
  ] do
  # ...
end
```

## NSFW Commands

Mark a command as age-restricted:

```elixir
command "nsfw-thing", "Only in age-restricted channels",
  nsfw: true do
  reply!(ctx, "This only works in age-restricted channels.")
end
```

## Context Menu Commands

User and message context menu commands show up in the right-click menu:

```elixir
user_command "User Info" do
  target_id = ctx.target_id
  user = resolved_user(ctx, target_id)
  reply!(ctx, "User: #{user.username} (#{target_id})")
end

message_command "Pin This" do
  target_id = ctx.target_id
  Lingo.pin_message(ctx.channel_id, target_id)
  reply!(ctx, "Pinned.")
end
```

Context menu commands have no description or options. Use `ctx.target_id` to get the ID of the targeted user or message, then use `resolved_user/2` or `resolved_message/2` to get the full object.

## Response Helpers

See [Context: Responding](/commands/context#responding) for the full list of response functions (`reply!`, `defer!`, `ephemeral`, `update!`, `show_modal!`, etc.).

## Registering Commands

Commands defined with the macros get compiled into your bot module. Push them to Discord with:

```elixir
# Global commands (can take up to an hour to show up)
Lingo.register_commands(MyBot.Bot)

# Guild commands (instant, good for development)
Lingo.register_commands_to_guild(MyBot.Bot, "GUILD_ID")
```

Call this once at startup or whenever your commands change. Lingo uses `bulk_overwrite`, so it replaces the full set each time: removed commands get deleted, new ones get added, changed ones get updated.
