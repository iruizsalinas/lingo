# Option Builders

Option builder functions are imported by `use Lingo.Bot`. They construct `Lingo.Type.CommandOption` structs for use in command definitions.

## Builders

All builders have the signature `name(name, description, opts \\ [])`.

### `string/3`

String option.

```elixir
string("query", "Search query", required: true, min_length: 1, max_length: 100)
```

### `integer/3`

Integer option.

```elixir
integer("count", "Number of items", min_value: 1, max_value: 100)
```

### `number/3`

Floating-point number option.

```elixir
number("ratio", "Scale ratio", min_value: 0.1, max_value: 10.0)
```

### `boolean/3`

Boolean option.

```elixir
boolean("ephemeral", "Send as ephemeral?")
```

### `user/3`

User option. Returns a snowflake ID. Use `get_user(ctx, :name)` to resolve.

```elixir
user("target", "The user", required: true)
```

### `role/3`

Role option. Returns a snowflake ID.

```elixir
role("role", "The role to assign", required: true)
```

### `channel/3`

Channel option. Returns a snowflake ID. Use `channel_types` to restrict.

```elixir
channel("channel", "The channel", channel_types: [:guild_text, :guild_announcement])
```

### `mentionable/3`

User or role option. Returns a snowflake ID.

```elixir
mentionable("target", "User or role")
```

### `attachment/3`

File attachment option. Returns a snowflake ID. Use `resolved_attachment(ctx, id)` to get the attachment data.

```elixir
attachment("file", "Upload a file", required: true)
```

### `subcommand/3`

Subcommand. Use `options:` to define the subcommand's own options.

```elixir
subcommand("add", "Add an item",
  options: [
    string("name", "Item name", required: true)
  ]
)
```

### `subcommand_group/3`

Group of subcommands. Use `options:` to list subcommands.

```elixir
subcommand_group("items", "Manage items",
  options: [
    subcommand("add", "Add an item", options: [...]),
    subcommand("remove", "Remove an item", options: [...])
  ]
)
```

## Common Options

All builders accept these keyword options:

| Option | Type | Default | Applies To |
|--------|------|---------|-----------|
| `required` | `boolean` | `false` | All |
| `choices` | `list` | `[]` | `string`, `integer`, `number` |
| `autocomplete` | `boolean` | `false` | `string`, `integer`, `number` |
| `min_value` | `number` | `nil` | `integer`, `number` |
| `max_value` | `number` | `nil` | `integer`, `number` |
| `min_length` | `integer` | `nil` | `string` |
| `max_length` | `integer` | `nil` | `string` |
| `channel_types` | `list` | `[]` | `channel` |
| `options` | `list` | `[]` | `subcommand`, `subcommand_group` |
| `name_localizations` | `map` | `nil` | All |
| `description_localizations` | `map` | `nil` | All |

## Choices Format

Choices can be maps with `"name"` and `"value"` keys, or keyword lists:

```elixir
# Map format
choices: [
  %{"name" => "Red", "value" => "red"},
  %{"name" => "Blue", "value" => "blue"}
]

# Keyword list format
choices: [
  [name: "Red", value: "red"],
  [name: "Blue", value: "blue"]
]
```
