# Components

Component builder functions for messages, modals, and v2 components. All are called on the `Lingo` module.

## Action Row

```elixir
Lingo.action_row(components)
```

Wraps components in an action row. Required for buttons and select menus. Max 5 buttons or 1 select per row.

## Buttons

```elixir
Lingo.button(opts)
```

| Option | Type | Description |
|--------|------|-------------|
| `custom_id` | string | Required (except for `:link` style) |
| `label` | string | Button text |
| `style` | atom | `:primary`, `:secondary`, `:success`, `:danger`, `:link`, `:premium` |
| `emoji` | map | `%{name: "fire", id: "123"}` or `%{name: "fire"}` for unicode |
| `url` | string | URL for link buttons |
| `disabled` | boolean | Default `false` |

```elixir
Lingo.button(custom_id: "yes", label: "Confirm", style: :success)
Lingo.button(url: "https://example.com", label: "Visit", style: :link)
Lingo.button(custom_id: "react", emoji: %{name: "thumbsup"}, style: :secondary)
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
Lingo.string_select("color",
  placeholder: "Pick a color",
  options: [
    Lingo.select_option("Red", "red", description: "Warm"),
    Lingo.select_option("Blue", "blue", emoji: %{name: "blue_circle"})
  ]
)
```

### Auto-Populated Selects

These don't take `options`. Discord populates them.

```elixir
Lingo.user_select(custom_id, opts \\ [])
Lingo.role_select(custom_id, opts \\ [])
Lingo.mentionable_select(custom_id, opts \\ [])
Lingo.channel_select(custom_id, opts \\ [])
```

All accept `placeholder`, `min_values`, `max_values`, and `disabled`.

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

## Text Input

```elixir
Lingo.text_input(custom_id, label, opts \\ [])
Lingo.text_input(custom_id, opts)
```

| Option | Type | Description |
|--------|------|-------------|
| `style` | atom | `:short` (default) or `:paragraph` |
| `min_length` | integer | Minimum length |
| `max_length` | integer | Maximum length |
| `required` | boolean | Default `false` |
| `value` | string | Pre-filled value |
| `placeholder` | string | Placeholder text |
| `label` | string | Label (if not passed as second arg) |

```elixir
Lingo.text_input("name", "Your Name", required: true, max_length: 50)
Lingo.text_input("bio", "About You", style: :paragraph, placeholder: "Tell us about yourself")
```

## Modal

```elixir
Lingo.modal(custom_id, title, components)
```

Helper that builds the modal payload. `components` should be a list of action rows containing text inputs.

```elixir
Lingo.modal("feedback", "Feedback Form", [
  Lingo.action_row([
    Lingo.text_input("subject", "Subject", required: true)
  ]),
  Lingo.action_row([
    Lingo.text_input("body", "Details", style: :paragraph)
  ])
])
```

## V2 Message Components

These components require the `components_v2` message flag.

### Section

```elixir
Lingo.section(text_displays, accessory)
```

A section with text and an optional accessory (thumbnail or button).

### Text Display

```elixir
Lingo.text_display(content)
```

A text block inside a section or container.

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

`items` is a list of gallery items.

### Gallery Item

```elixir
Lingo.gallery_item(url, opts \\ [])
```

| Option | Type | Description |
|--------|------|-------------|
| `description` | string | Caption |
| `spoiler` | boolean | Blur the media |

### Unfurled Media

```elixir
Lingo.unfurled_media(url)
```

Wraps a URL for use in thumbnails and gallery items.

### File

```elixir
Lingo.file(url, opts \\ [])
```

| Option | Type |
|--------|------|
| `spoiler` | boolean |

### Separator

```elixir
Lingo.separator(opts \\ [])
```

| Option | Type | Description |
|--------|------|-------------|
| `divider` | boolean | Show a line |
| `spacing` | atom | `:small` or `:large` |

### Container

```elixir
Lingo.container(components, opts \\ [])
```

| Option | Type | Description |
|--------|------|-------------|
| `color` | integer | Accent color |
| `spoiler` | boolean | Blur contents |

### Components V2 Flag

```elixir
Lingo.components_v2_flag()
```

Returns the integer flag value to enable v2 components on a message:

```elixir
Lingo.send_message(channel_id, %{
  flags: Lingo.components_v2_flag(),
  components: [
    Lingo.container([
      Lingo.text_display("Hello from v2 components!")
    ], color: 0x5865F2)
  ]
})
```

## Modal-Specific Components

### Label

```elixir
Lingo.label(label_text, component, opts \\ [])
```

### File Upload

```elixir
Lingo.file_upload(custom_id, opts \\ [])
```

### Radio Group

```elixir
Lingo.radio_group(custom_id, options, opts \\ [])
```

### Checkbox Group

```elixir
Lingo.checkbox_group(custom_id, options, opts \\ [])
```

### Checkbox

```elixir
Lingo.checkbox(custom_id, opts \\ [])
```
