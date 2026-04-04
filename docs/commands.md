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

Add options with the `options:` keyword. Use the [option builder functions](/option-builders) to define each one:

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

`option(ctx, :name)` retrieves the value of an option by name. For `user`, `role`, `channel`, and `mentionable` types, the value is a snowflake ID. Use the `get_*` shortcuts to resolve the full object:

```elixir
user_obj = get_user(ctx, :target)      # Lingo.Type.User or nil
role_obj = get_role(ctx, :role)        # Lingo.Type.Role or nil
channel_obj = get_channel(ctx, :channel) # Lingo.Type.Channel or nil
member_obj = get_member(ctx, :target)  # Lingo.Type.Member or nil
```

## Option Types

| Builder | Discord Type | Value |
|---------|-------------|-------|
| `string/3` | String | `String.t()` |
| `integer/3` | Integer | `integer()` |
| `number/3` | Number | `float()` |
| `boolean/3` | Boolean | `boolean()` |
| `user/3` | User | snowflake ID |
| `role/3` | Role | snowflake ID |
| `channel/3` | Channel | snowflake ID |
| `mentionable/3` | Mentionable | snowflake ID |
| `attachment/3` | Attachment | snowflake ID |

All option builders accept these keyword options:

| Option | Type | Default |
|--------|------|---------|
| `required` | `boolean` | `false` |
| `choices` | `list` | `[]` |
| `autocomplete` | `boolean` | `false` |
| `min_value` / `max_value` | `number` | `nil` |
| `min_length` / `max_length` | `integer` | `nil` |
| `channel_types` | `list` | `[]` |

## Choices

Lock an option to a fixed set of values:

```elixir
command "color", "Pick a color",
  options: [
    string("color", "Your color",
      required: true,
      choices: [
        %{"name" => "Red", "value" => "red"},
        %{"name" => "Blue", "value" => "blue"},
        %{"name" => "Green", "value" => "green"}
      ]
    )
  ] do
  reply!(ctx, "You picked #{option(ctx, :color)}.")
end
```

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

These are available inside command blocks:

| Function | What it does |
|----------|-------------|
| `reply!(ctx, data)` | Send a response. Raises on failure. |
| `reply(ctx, data)` | Send a response. Returns `{:ok, ctx}` or `{:error, reason}`. |
| `ephemeral(ctx, data)` | Send an ephemeral response (only the user sees it). |
| `defer!(ctx)` | Acknowledge the interaction. Follow up with `reply!` later. |
| `defer!(ctx, ephemeral: true)` | Defer with an ephemeral loading state. |
| `update!(ctx, data)` | Edit the message a component is attached to. |
| `show_modal!(ctx, modal)` | Pop open a modal dialog. |

`data` can be a string (sent as `content`) or a map with any combination of `content`, `embeds`, `components`, `flags`, `files`, etc.

After calling `reply!` once, any further `reply!` calls send followup messages.

## Registering Commands

Commands defined with the macros get compiled into your bot module. Push them to Discord with:

```elixir
# Global commands (can take up to an hour to show up)
Lingo.register_commands(MyBot.Bot)

# Guild commands (instant, good for development)
Lingo.register_commands_to_guild(MyBot.Bot, "GUILD_ID")
```

Call this once at startup or whenever your commands change. Lingo uses `bulk_overwrite`, so it replaces the full set each time: removed commands get deleted, new ones get added, changed ones get updated.
