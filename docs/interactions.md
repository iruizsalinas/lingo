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

See [Message Components: Buttons](/commands/message-components#buttons) for all styles and options.

## Select Menus

```elixir
command "pick", "Pick a color" do
  reply!(ctx, %{
    content: "Pick one:",
    components: [
      Lingo.action_row([
        Lingo.string_select("color_select",
          options: [
            Lingo.select_option("Red", "red"),
            Lingo.select_option("Blue", "blue")
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

See [Message Components: Select Menus](/commands/message-components#select-menus) for all select types.

## Modals

Show a modal form from a command or component interaction:

```elixir
command "feedback", "Send feedback" do
  show_modal!(ctx, Lingo.modal("feedback_modal", "Feedback", [
    Lingo.label("Subject", Lingo.text_input("subject", required: true)),
    Lingo.label("Details", Lingo.text_input("body", style: :paragraph))
  ]))
end

modal "feedback_modal", ctx do
  subject = modal_value(ctx, :subject)
  body = modal_value(ctx, :body)
  reply!(ctx, "#{subject}: #{body}")
end
```

`modal_value(ctx, :field_id)` gets a field's value by its custom ID. See [Modal Components](/commands/modal-components) for all modal component types.

## Autocomplete

Give users dynamic suggestions as they type:

```elixir
command "search", "Search for something",
  options: [
    string("query", "Search query", required: true, autocomplete: true)
  ] do
  reply!(ctx, "You searched for: #{option(ctx, :query)}")
end

autocomplete "search", ctx do
  {_name, value} = focused_option(ctx)

  results =
    ["Elixir", "Rust", "Go", "TypeScript"]
    |> Enum.filter(&String.starts_with?(String.downcase(&1), String.downcase(value)))
    |> Enum.map(&%{name: &1, value: &1})

  autocomplete_result(ctx, results)
end
```

`focused_option(ctx)` returns `{name, current_value}` for the option being typed. `autocomplete_result(ctx, choices)` sends the choices back. Each choice needs `:name` and `:value` keys.

The autocomplete handler has 3 seconds to respond.

## Collectors

Wait for a button click or reaction inside a command handler, without a separate `component` macro.

### Awaiting a Component

```elixir
command "confirm", "Delete messages?" do
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

`await_component/2` blocks until someone clicks a button or select menu on that message. The interaction is consumed and won't reach your `component` handlers.

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
```

`collect_reactions/3` gathers all matching reactions during the timeout window and returns them as a list.

See [Helpers: Collectors](/utilities/helpers#collectors) for the full option tables.
