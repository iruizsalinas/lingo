# Presence

## Initial Presence

Set the bot's status on connect:

```elixir
{Lingo,
 bot: MyBot.Bot,
 token: token,
 intents: intents,
 presence: [status: :online, text: "with Elixir"]}
```

| Option | Type | Default |
|--------|------|---------|
| `status` | atom | `:online` |
| `text` | string | `nil` |
| `activity` | `Activity` struct | `nil` |

`text` sets a "Playing" activity. For more control, pass a struct:

```elixir
presence: [
  status: :dnd,
  activity: %Lingo.Type.Activity{name: "music", type: :listening}
]
```

## Updating at Runtime

```elixir
Lingo.update_presence(:online, text: "something new")
Lingo.update_presence(:idle)
Lingo.update_presence(:dnd, activity: %Lingo.Type.Activity{name: "music", type: :listening})
```

Broadcasts to all shards.

## Status Values

`:online`, `:idle`, `:dnd`, `:invisible`

## Activity Types

| Type | Display |
|------|---------|
| `:playing` | "Playing {name}" |
| `:streaming` | "Streaming {name}" (requires `url`) |
| `:listening` | "Listening to {name}" |
| `:watching` | "Watching {name}" |
| `:custom` | "{state}" or "{emoji} {state}" |
| `:competing` | "Competing in {name}" |
