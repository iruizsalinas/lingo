# Context

`Lingo.Command.Context` is the struct passed as `ctx` to command, component, modal, and autocomplete handlers.

## Fields

### Who triggered it

| Field | Type | Description |
|-------|------|-------------|
| `user_id` | `String.t() \| nil` | ID of the user |
| `user` | `User.t() \| nil` | The user |
| `member` | `Member.t() \| nil` | Guild member data (nil in DMs) |

### Where it happened

| Field | Type | Description |
|-------|------|-------------|
| `guild_id` | `String.t() \| nil` | Guild ID (nil in DMs) |
| `channel_id` | `String.t() \| nil` | Channel ID |

### What was sent

| Field | Type | Description |
|-------|------|-------------|
| `command_name` | `String.t() \| nil` | Command name (commands, autocomplete) |
| `options` | `map()` | Parsed options, keys are atoms |
| `raw_options` | `[map()] \| nil` | Unparsed options from the API |
| `resolved` | `map() \| nil` | Resolved objects for user/role/channel options |
| `target_id` | `String.t() \| nil` | Target for context menu commands |
| `custom_id` | `String.t() \| nil` | Component or modal custom ID |
| `values` | `[String.t()]` | Selected values from a select menu |
| `message` | `Message.t() \| nil` | Message a component is attached to |
| `component_type` | `integer() \| nil` | Component type integer |

### Response state

| Field | Type | Description |
|-------|------|-------------|
| `replied` | `boolean()` | Whether a response has been sent |
| `deferred` | `boolean()` | Whether the interaction has been deferred |

### Identifiers

| Field | Type | Description |
|-------|------|-------------|
| `interaction_id` | `String.t()` | The interaction's snowflake ID |
| `interaction_token` | `String.t()` | Token for responding |
| `application_id` | `String.t()` | Your application's ID |

## Responding

### reply / reply!

```elixir
reply!(ctx, "Hello!")
reply!(ctx, %{content: "Hello!", embeds: [embed]})
```

Send a response. `reply!` returns `ctx` on success, raises on failure. `reply` returns `{:ok, ctx}` or `{:error, reason}`.

- First call sends the initial response
- After a `defer!`, edits the deferred message
- After the first reply, sends a followup message

`data` can be a string or a map.

### update / update!

```elixir
update!(ctx, %{content: "Updated.", components: []})
```

Edit the message a component is attached to. Only makes sense in component handlers.

### defer / defer!

```elixir
ctx = defer!(ctx)
ctx = defer!(ctx, ephemeral: true)
ctx = defer!(ctx, update: true)
```

Acknowledge the interaction without sending content yet. Follow up with `reply!` or `update!` later.

| Option | What it does |
|--------|-------------|
| `ephemeral` | Deferred message will be ephemeral |
| `update` | Defer as a message update (for components) |

No-ops if already deferred.

### ephemeral

```elixir
ephemeral(ctx, "Only you can see this.")
ephemeral(ctx, %{content: "Secret.", embeds: [embed]})
```

Send a response only the invoking user sees.

### show_modal / show_modal!

```elixir
show_modal!(ctx, Lingo.modal("my_modal", "Title", components))
```

Pop open a modal dialog. Can't be used after a defer or reply.

### autocomplete_result

```elixir
autocomplete_result(ctx, [%{name: "Option 1", value: "opt1"}])
```

Send autocomplete choices. Only for autocomplete handlers.

## Reading Options

### option

```elixir
option(ctx, :name)
option(ctx, :count)
```

Get a command option value by name. For subcommands, returns nested maps:

```elixir
# /config roles autorole role:@Mod
option(ctx, :roles)  # %{autorole: %{role: "123456"}}
```

### modal_value

```elixir
modal_value(ctx, :field_id)
```

Get a text input value from a modal submission. Same as `option/2`.

### focused_option

```elixir
{name, current_value} = focused_option(ctx)
```

For autocomplete handlers. Returns the option the user is currently typing in, or `nil`.

## Resolved Data

When a command option is a user/role/channel type, the resolved object comes along with the ID.

### Direct lookup

```elixir
resolved_user(ctx, user_id)        # User or nil
resolved_member(ctx, user_id)      # Member or nil
resolved_role(ctx, role_id)        # Role or nil
resolved_channel(ctx, channel_id)  # Channel or nil
resolved_message(ctx, message_id)  # Message or nil
resolved_attachment(ctx, att_id)   # Attachment or nil
```

### From an option name

These get the ID from the option and resolve it in one step:

```elixir
command "info", "Get user info",
  options: [user("target", "The user", required: true)] do
  user = get_user(ctx, :target)
  member = get_member(ctx, :target)
  reply!(ctx, "#{user.username} joined #{member.joined_at}")
end
```

| Function | Returns |
|----------|---------|
| `get_user(ctx, option_name)` | `User` or `nil` |
| `get_role(ctx, option_name)` | `Role` or `nil` |
| `get_channel(ctx, option_name)` | `Channel` or `nil` |
| `get_member(ctx, option_name)` | `Member` or `nil` |
