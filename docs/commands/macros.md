# Bot DSL

All macros become available after `use Lingo.Bot`.

## `command/3` and `command/4`

```elixir
command name, description, opts \\ [], do: body
```

Defines a slash command.

| Argument | Type | Description |
|----------|------|-------------|
| `name` | string | Command name (1-32 chars, lowercase, no spaces) |
| `description` | string | Command description (1-100 chars) |
| `opts` | keyword | Optional settings (below) |
| `body` | block | Handler code. `ctx` is bound to `Lingo.Command.Context.t()` |

### Options

| Key | Type | Description |
|-----|------|-------------|
| `options` | list | List of [option builders](/commands/option-builders) |
| `default_member_permissions` | integer | Permission bitfield required to use this command |
| `nsfw` | boolean | Restrict to age-gated channels. Default `false` |
| `integration_types` | list | Where the command can be installed |
| `contexts` | list | Where the command can be used |

```elixir
command "purge", "Delete messages",
  default_member_permissions: Lingo.Permissions.resolve([:manage_messages]),
  options: [
    integer("count", "Number of messages", required: true, min_value: 1, max_value: 100)
  ] do
  count = option(ctx, :count)
  {:ok, messages} = Lingo.list_messages(ctx.channel_id, limit: count)
  ids = Enum.map(messages, & &1["id"])
  Lingo.bulk_delete_messages(ctx.channel_id, ids, reason: "Purge by #{ctx.user.username}")
  ephemeral(ctx, "Deleted #{length(ids)} messages.")
end
```

## `handle/3`

```elixir
handle event_name, var, do: body
```

Defines a gateway event handler.

| Argument | Type | Description |
|----------|------|-------------|
| `event_name` | atom | The event (e.g., `:message_create`) |
| `var` | variable | Binds the event data |
| `body` | block | Handler code |

```elixir
handle :message_create, msg do
  if msg.content =~ ~r/bad word/i do
    Lingo.delete_message(msg.channel_id, msg.id)
  end
end
```

You can have multiple handlers for different events. One handler per event name.

## `component/3`

```elixir
component custom_id, var, do: body
```

Handles message component interactions (buttons, select menus).

| Argument | Type | Description |
|----------|------|-------------|
| `custom_id` | string | The component's `custom_id` |
| `var` | variable | Binds `Lingo.Command.Context.t()` |
| `body` | block | Handler code |

```elixir
component "role_select", ctx do
  [role_id] = ctx.values
  Lingo.add_member_role(ctx.guild_id, ctx.user_id, role_id)
  ephemeral(ctx, "Role added!")
end
```

`ctx.values` has the selected values. `ctx.custom_id` is the component's ID. `ctx.message` is the message it's on. `ctx.component_type` is the type integer.

If no `component` macro matches, the interaction falls through to `handle :interaction_create` if you have one.

## `modal/3`

```elixir
modal custom_id, var, do: body
```

Handles modal form submissions.

| Argument | Type | Description |
|----------|------|-------------|
| `custom_id` | string | The modal's `custom_id` |
| `var` | variable | Binds `Lingo.Command.Context.t()` |
| `body` | block | Handler code |

```elixir
modal "report_modal", ctx do
  reason = modal_value(ctx, :reason)
  reply!(ctx, "Report submitted: #{reason}")
end
```

Use `modal_value(ctx, :field_id)` to pull values out. The field ID is the text input's `custom_id`.

Falls through to `handle :interaction_create` if no `modal` macro matches.

## `autocomplete/3`

```elixir
autocomplete command_name, var, do: body
```

Provides autocomplete suggestions for a command's options.

| Argument | Type | Description |
|----------|------|-------------|
| `command_name` | string | Which command to provide autocomplete for |
| `var` | variable | Binds `Lingo.Command.Context.t()` |
| `body` | block | Must call `autocomplete_result(ctx, choices)` |

```elixir
autocomplete "tag", ctx do
  {_name, typed} = focused_option(ctx)

  choices =
    get_all_tags()
    |> Enum.filter(&String.starts_with?(&1, typed))
    |> Enum.take(25)
    |> Enum.map(&%{name: &1, value: &1})

  autocomplete_result(ctx, choices)
end
```

## `user_command/2`

```elixir
user_command name, do: body
```

Defines a user context menu command (right-click a user).

```elixir
user_command "Report User" do
  target_id = ctx.target_id
  user = resolved_user(ctx, target_id)
  reply!(ctx, "Reported #{user.username}.")
end
```

## `message_command/2`

```elixir
message_command name, do: body
```

Defines a message context menu command (right-click a message).

```elixir
message_command "Bookmark" do
  target_id = ctx.target_id
  msg = resolved_message(ctx, target_id)
  dm = Lingo.create_dm(ctx.user_id)
  Lingo.send_message(dm["id"], content: "Bookmarked: #{msg.content}")
  ephemeral(ctx, "Bookmarked.")
end
```

