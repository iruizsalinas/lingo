# Interactions

Beyond slash commands, Lingo supports buttons, select menus, modals, and autocomplete through dedicated macros.

## Buttons

Send a message with buttons using `action_row/1` and `button/1`:

```elixir
command "confirm", "Ask for confirmation" do
  reply!(ctx, %{
    content: "Are you sure?",
    components: [
      Lingo.action_row([
        Lingo.button(custom_id: "confirm_yes", label: "Yes", style: :success),
        Lingo.button(custom_id: "confirm_no", label: "No", style: :danger)
      ])
    ]
  })
end
```

Handle button clicks with `component`:

```elixir
component "confirm_yes", ctx do
  update!(ctx, %{content: "Confirmed.", components: []})
end

component "confirm_no", ctx do
  update!(ctx, %{content: "Cancelled.", components: []})
end
```

The `ctx` in a component handler is the same `Lingo.Command.Context` struct. Use `update!/2` to edit the message the button lives on, or `reply!/2` to send a new message.

### Button Styles

| Style | Look |
|-------|------|
| `:primary` | Blurple |
| `:secondary` | Grey |
| `:success` | Green |
| `:danger` | Red |
| `:link` | Grey with link icon (needs `url`, no `custom_id`) |
| `:premium` | Blurple with premium badge (needs `sku_id`) |

```elixir
Lingo.button(custom_id: "my_btn", label: "Click", style: :primary)
Lingo.button(url: "https://example.com", label: "Visit", style: :link)
Lingo.button(custom_id: "my_btn", emoji: %{name: "fire", id: "123"})
```

## Select Menus

```elixir
command "pick-color", "Pick a color" do
  reply!(ctx, %{
    content: "Choose a color:",
    components: [
      Lingo.action_row([
        Lingo.string_select("color_select",
          placeholder: "Pick one...",
          options: [
            Lingo.select_option("Red", "red", description: "A warm color"),
            Lingo.select_option("Blue", "blue", description: "A cool color"),
            Lingo.select_option("Green", "green")
          ]
        )
      ])
    ]
  })
end

component "color_select", ctx do
  [color] = ctx.values
  update!(ctx, %{content: "You picked: #{color}", components: []})
end
```

`ctx.values` is a list of selected values. For single-select it has one element.

### Select Menu Types

| Builder | What the user picks |
|---------|-------------------|
| `Lingo.string_select/2` | From your predefined options |
| `Lingo.user_select/2` | Users |
| `Lingo.role_select/2` | Roles |
| `Lingo.mentionable_select/2` | Users or roles |
| `Lingo.channel_select/2` | Channels |

Auto-populated selects (user, role, etc.) don't need `options`. They return snowflake IDs in `ctx.values`.

## Modals

Show a modal form from a command or component interaction:

```elixir
command "feedback", "Send feedback" do
  show_modal!(ctx, Lingo.modal("feedback_modal", "Send Feedback", [
    Lingo.action_row([
      Lingo.text_input("subject", "Subject", required: true, max_length: 100)
    ]),
    Lingo.action_row([
      Lingo.text_input("body", "Your feedback", style: :paragraph, required: true)
    ])
  ]))
end
```

Handle submissions with `modal`:

```elixir
modal "feedback_modal", ctx do
  subject = modal_value(ctx, :subject)
  body = modal_value(ctx, :body)
  reply!(ctx, "Thanks for your feedback on **#{subject}**!")
end
```

`modal_value(ctx, :field_id)` gets a text input's value by its custom ID.

### Text Input Styles

Default is `:short` (single line). Use `style: :paragraph` for multi-line.

## Autocomplete

Give users dynamic suggestions as they type:

```elixir
command "search", "Search for something",
  options: [
    string("query", "Search query", required: true, autocomplete: true)
  ] do
  query = option(ctx, :query)
  reply!(ctx, "You searched for: #{query}")
end

autocomplete "search", ctx do
  {_name, value} = focused_option(ctx)

  results =
    all_items()
    |> Enum.filter(&String.contains?(String.downcase(&1), String.downcase(value)))
    |> Enum.take(25)
    |> Enum.map(&%{name: &1, value: &1})

  autocomplete_result(ctx, results)
end
```

`focused_option(ctx)` returns `{name, current_value}` for the option being typed. `autocomplete_result(ctx, choices)` sends the choices back. Each choice needs `:name` and `:value` keys.

The autocomplete handler has 3 seconds to respond.

## Deferring

If your handler needs more than 3 seconds, defer the interaction first:

```elixir
command "slow", "This takes a while" do
  ctx = defer!(ctx)
  Process.sleep(5000)
  reply!(ctx, "Done!")
end
```

After deferring, the user sees a "thinking..." indicator. Call `reply!` to send the real response.

For ephemeral deferred responses:

```elixir
ctx = defer!(ctx, ephemeral: true)
```

For component interactions that need to defer an update:

```elixir
component "slow_button", ctx do
  ctx = defer!(ctx, update: true)
  Process.sleep(3000)
  update!(ctx, %{content: "Updated after delay."})
end
```

## Ephemeral Messages

Send a response only the invoking user can see:

```elixir
command "secret", "Secret info" do
  ephemeral(ctx, "Only you can see this.")
end
```

Or with richer content:

```elixir
ephemeral(ctx, %{content: "Only you.", embeds: [embed]})
```

## Collectors

Sometimes you want to wait for a button click or reaction right inside a command handler, without setting up a separate `component` macro. Collectors do that.

### Awaiting a Component

```elixir
command "confirm", "Delete all messages?" do
  {:ok, msg} = reply(ctx, %{
    content: "Are you sure?",
    components: [
      Lingo.action_row([
        Lingo.button(custom_id: "yes", label: "Yes", style: :danger),
        Lingo.button(custom_id: "no", label: "No", style: :secondary)
      ])
    ]
  })

  case Lingo.await_component(msg.id, timeout: 15_000) do
    {:ok, interaction} ->
      if interaction.data["custom_id"] == "yes" do
        # do the thing
      end

    :timeout ->
      Lingo.edit_message(ctx.channel_id, msg.id, %{content: "Timed out.", components: []})
  end
end
```

`await_component/2` blocks until someone clicks a button or select menu on that message. When it fires, the interaction is consumed and won't reach your `component` handlers.

Pass a `:filter` function to only match specific interactions:

```elixir
Lingo.await_component(msg.id,
  timeout: 30_000,
  filter: fn interaction -> interaction.user_id == ctx.user_id end
)
```

### Awaiting a Reaction

```elixir
case Lingo.await_reaction(channel_id, message_id, timeout: 30_000) do
  {:ok, reaction} ->
    IO.puts("#{reaction.user_id} reacted with #{reaction.emoji.name}")

  :timeout ->
    IO.puts("Nobody reacted")
end
```

Unlike component collectors, reaction collectors don't consume the event, so your `handle :message_reaction_add` still fires.

### Collecting Multiple Reactions

```elixir
{:ok, reactions} = Lingo.collect_reactions(channel_id, message_id,
  timeout: 10_000,
  filter: fn r -> r.user_id != bot_id end
)

IO.puts("Got #{length(reactions)} reactions in 10 seconds")
```

`collect_reactions/3` gathers all matching reactions during the timeout window and returns them as a list.
