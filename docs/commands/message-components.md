# Message Components

Builder functions for components in messages. All on the `Lingo` module.

## Action Row

```elixir
Lingo.action_row(components)
```

Wraps interactive components. Required for buttons and select menus. Max 5 buttons or 1 select per row.

```elixir
Lingo.action_row([
  Lingo.button(custom_id: "yes", label: "Yes", style: :success),
  Lingo.button(custom_id: "no", label: "No", style: :danger)
])
```

## Buttons

```elixir
Lingo.button(opts)
```

| Option | Type | Description |
|--------|------|-------------|
| `custom_id` | string | Required (except for `:link`) |
| `label` | string | Button text |
| `style` | atom | `:primary`, `:secondary`, `:success`, `:danger`, `:link`, `:premium` |
| `emoji` | map | `%{name: "fire", id: "123"}` for custom, `%{name: "thumbsup"}` for unicode |
| `url` | string | URL for link buttons |
| `disabled` | boolean | Default `false` |
| `sku_id` | string | SKU for premium buttons |

```elixir
reply!(ctx, %{
  content: "Are you sure?",
  components: [
    Lingo.action_row([
      Lingo.button(custom_id: "yes", label: "Yes", style: :success),
      Lingo.button(custom_id: "no", label: "No", style: :danger)
    ])
  ]
})
```

```elixir
component "yes", ctx do
  update!(ctx, %{content: "Done.", components: []})
end
```

## Select Menus

### String Select

```elixir
Lingo.string_select(custom_id, opts \\ [])
```

| Option | Type | Description |
|--------|------|-------------|
| `options` | list | List of `Lingo.select_option/3` |
| `placeholder` | string | Placeholder text |
| `min_values` | integer | Minimum selections |
| `max_values` | integer | Maximum selections |
| `disabled` | boolean | Default `false` |

```elixir
reply!(ctx, %{
  content: "Pick one:",
  components: [
    Lingo.action_row([
      Lingo.string_select("color",
        options: [
          Lingo.select_option("Red", "red"),
          Lingo.select_option("Blue", "blue")
        ]
      )
    ])
  ]
})
```

```elixir
component "color", ctx do
  [picked] = ctx.values
  update!(ctx, %{content: "You picked: #{picked}", components: []})
end
```

For multi-select, set `min_values` and `max_values`. `ctx.values` will contain all selected values.

### User, Role, Channel & Mentionable Selects

Discord populates these automatically. All return snowflake IDs in `ctx.values`.

```elixir
Lingo.user_select(custom_id, opts \\ [])
Lingo.role_select(custom_id, opts \\ [])
Lingo.mentionable_select(custom_id, opts \\ [])
Lingo.channel_select(custom_id, opts \\ [])
```

All accept `placeholder`, `min_values`, `max_values`, and `disabled`.

```elixir
Lingo.action_row([Lingo.user_select("pick_user")])
Lingo.action_row([Lingo.role_select("pick_role")])
Lingo.action_row([Lingo.channel_select("pick_channel")])
Lingo.action_row([Lingo.mentionable_select("pick_mention")])
```

```elixir
component "pick_user", ctx do
  [user_id] = ctx.values
  update!(ctx, %{content: "Picked: <@#{user_id}>", components: []})
end
```

### Select Option

```elixir
Lingo.select_option(label, value, opts \\ [])
```

| Option | Type | Description |
|--------|------|-------------|
| `description` | string | Option description |
| `emoji` | map | Emoji to display |
| `default` | boolean | Pre-selected |

### Default Value

Pre-populate auto-populated selects:

```elixir
Lingo.default_value(id, type)
```

`type` is `:user`, `:role`, or `:channel`.

```elixir
Lingo.user_select("pick_user",
  default_values: [Lingo.default_value("123456789", :user)]
)
```

## V2 Components

These require the [components v2 flag](#components-v2-flag) on the message.

### Container

```elixir
Lingo.container(components, opts \\ [])
```

| Option | Type | Description |
|--------|------|-------------|
| `color` | integer | Accent color |
| `spoiler` | boolean | Blur contents |

Top-level wrapper for v2 components:

```elixir
reply!(ctx, %{
  flags: Lingo.v2(),
  components: [
    Lingo.container([
      Lingo.text_display("Hello from v2 components!")
    ], color: 0x5865F2)
  ]
})
```

### Text Display

```elixir
Lingo.text_display(content)
```

A markdown text block:

```elixir
Lingo.text_display("Hello **world**")
```

### Section

```elixir
Lingo.section(text_displays, accessory)
```

Text with an accessory (thumbnail or button):

```elixir
Lingo.section(
  [Lingo.text_display("**Lingo**\nA Discord library")],
  Lingo.thumbnail("https://picsum.photos/id/42/200/200")
)
```

```elixir
Lingo.section(
  [Lingo.text_display("Click to confirm.")],
  Lingo.button(custom_id: "ok", label: "OK", style: :success)
)
```

### Thumbnail

```elixir
Lingo.thumbnail(url, opts \\ [])
```

| Option | Type | Description |
|--------|------|-------------|
| `description` | string | Alt text |
| `spoiler` | boolean | Blur the image |

### Media Gallery

```elixir
Lingo.media_gallery(items)
```

```elixir
Lingo.media_gallery([
  Lingo.gallery_item("https://picsum.photos/id/10/400/300"),
  Lingo.gallery_item("https://picsum.photos/id/20/400/300", description: "Caption")
])
```

### Gallery Item

```elixir
Lingo.gallery_item(url, opts \\ [])
```

| Option | Type | Description |
|--------|------|-------------|
| `description` | string | Caption |
| `spoiler` | boolean | Blur the media |

### File

```elixir
Lingo.file(url, opts \\ [])
```

| Option | Type |
|--------|------|
| `spoiler` | boolean |

Use `attachment://filename` to reference files sent in the same message:

```elixir
reply!(ctx, %{
  flags: Lingo.v2(),
  files: [{"data.txt", "Some content"}],
  components: [
    Lingo.container([
      Lingo.file("attachment://data.txt")
    ])
  ]
})
```

### Separator

```elixir
Lingo.separator(opts \\ [])
```

| Option | Type | Description |
|--------|------|-------------|
| `divider` | boolean | Show a line |
| `spacing` | atom | `:small` or `:large` |

```elixir
Lingo.container([
  Lingo.text_display("Above"),
  Lingo.separator(divider: true, spacing: :large),
  Lingo.text_display("Below")
])
```

### Unfurled Media

```elixir
Lingo.unfurled_media(url)
```

Low-level helper that wraps a URL into `%{url: url}`. You generally don't need this since `thumbnail/2`, `gallery_item/2`, and `file/2` handle URL wrapping automatically.

### V2 Flag

```elixir
Lingo.v2()
```

Returns the flag value (`32768`) to enable v2 components. Required in `:flags` when using containers, sections, text displays, galleries, separators, or files:

```elixir
reply!(ctx, %{
  flags: Lingo.v2(),
  components: [...]
})
```
