# Modal Components

Builder functions for modal components. All on the `Lingo` module.

## Modal Builder

```elixir
Lingo.modal(custom_id, title, components)
```

Builds a modal payload. Components go at the top level, wrapped in Labels.

```elixir
command "feedback", "Send feedback" do
  show_modal!(ctx, Lingo.modal("fb_modal", "Feedback", [
    Lingo.label("Subject", Lingo.text_input("subject", required: true)),
    Lingo.label("Details", Lingo.text_input("body", style: :paragraph))
  ]))
end

modal "fb_modal", ctx do
  subject = modal_value(ctx, :subject)
  body = modal_value(ctx, :body)
  reply!(ctx, "#{subject}: #{body}")
end
```

## Label

```elixir
Lingo.label(label_text, component, opts \\ [])
```

| Option | Type | Description |
|--------|------|-------------|
| `description` | string | Additional description text |

Wraps a modal component with a label. Placed directly in the modal's components list.

```elixir
Lingo.label("Your name", Lingo.text_input("name", required: true))
Lingo.label("Color", Lingo.radio_group("color", [...]), description: "Pick one")
```

## Text Input

```elixir
Lingo.text_input(custom_id, label, opts \\ [])
```

| Option | Type | Description |
|--------|------|-------------|
| `style` | atom | `:short` (default) or `:paragraph` |
| `min_length` | integer | Minimum length |
| `max_length` | integer | Maximum length |
| `required` | boolean | Default `false` |
| `value` | string | Pre-filled value |
| `placeholder` | string | Placeholder text |

Inside a Label, omit the `label` argument:

```elixir
Lingo.label("Name", Lingo.text_input("name", required: true))
Lingo.label("Bio", Lingo.text_input("bio", style: :paragraph))
```

Text inputs also work in action rows (legacy):

```elixir
Lingo.action_row([Lingo.text_input("name", "Name", required: true)])
```

## Select Menus

All select menus work in modals. Wrap them in a Label.

### String Select

```elixir
command "prefs", "Set preferences" do
  show_modal!(ctx, Lingo.modal("prefs_modal", "Preferences", [
    Lingo.label("Color",
      Lingo.string_select("color",
        options: [
          Lingo.select_option("Red", "red"),
          Lingo.select_option("Blue", "blue")
        ]
      )
    )
  ]))
end

modal "prefs_modal", ctx do
  reply!(ctx, "Color: #{modal_value(ctx, :color)}")
end
```

### User, Role, Channel & Mentionable Selects

```elixir
Lingo.label("Pick a user", Lingo.user_select("target"))
Lingo.label("Pick a role", Lingo.role_select("role"))
Lingo.label("Pick a channel", Lingo.channel_select("channel"))
Lingo.label("Pick a user or role", Lingo.mentionable_select("mention"))
```

## Radio Group

```elixir
Lingo.radio_group(custom_id, options, opts \\ [])
```

| Option | Type | Description |
|--------|------|-------------|
| `required` | boolean | Whether a selection is required |

Single-choice selection. Options use `Lingo.select_option/3`. Must be wrapped in a Label. Supports 2-10 options.

```elixir
command "pick", "Pick a class" do
  show_modal!(ctx, Lingo.modal("pick_modal", "Pick", [
    Lingo.label("Class",
      Lingo.radio_group("class", [
        Lingo.select_option("Warrior", "warrior"),
        Lingo.select_option("Mage", "mage")
      ], required: true)
    )
  ]))
end

modal "pick_modal", ctx do
  reply!(ctx, "Class: #{modal_value(ctx, :class)}")
end
```

## Checkbox Group

```elixir
Lingo.checkbox_group(custom_id, options, opts \\ [])
```

| Option | Type | Description |
|--------|------|-------------|
| `min_values` | integer | Minimum selections |
| `max_values` | integer | Maximum selections |

Multi-selection from a list. Options use `Lingo.select_option/3`. Must be wrapped in a Label. Supports 2-10 options.

```elixir
command "topics", "Pick topics" do
  show_modal!(ctx, Lingo.modal("topics_modal", "Topics", [
    Lingo.label("Pick topics",
      Lingo.checkbox_group("topics", [
        Lingo.select_option("Backend", "backend"),
        Lingo.select_option("Frontend", "frontend")
      ])
    )
  ]))
end

modal "topics_modal", ctx do
  reply!(ctx, "Topics: #{inspect(modal_value(ctx, :topics))}")
end
```

## Checkbox

```elixir
Lingo.checkbox(custom_id, opts \\ [])
```

| Option | Type | Description |
|--------|------|-------------|
| `default` | boolean | Pre-checked state |

A single toggle. Must be wrapped in a Label.

```elixir
command "settings", "Settings" do
  show_modal!(ctx, Lingo.modal("settings_modal", "Settings", [
    Lingo.label("Notifications", Lingo.checkbox("notifs", default: true)),
    Lingo.label("Dark mode", Lingo.checkbox("dark"))
  ]))
end

modal "settings_modal", ctx do
  reply!(ctx, "Notifs: #{modal_value(ctx, :notifs)}, Dark: #{modal_value(ctx, :dark)}")
end
```

## File Upload

```elixir
Lingo.file_upload(custom_id, opts \\ [])
```

| Option | Type | Description |
|--------|------|-------------|
| `required` | boolean | Whether a file is required |
| `min_values` | integer | Minimum files |
| `max_values` | integer | Maximum files |
