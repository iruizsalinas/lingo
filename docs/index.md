# Getting Started

Zero to a running bot that responds to a slash command.

## Create the Project

```bash
mix new my_bot --sup
cd my_bot
```

Add lingo to your dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:lingo, "~> 0.2.0"}
  ]
end
```

```bash
mix deps.get
```

## Define Your Bot

Create `lib/my_bot/bot.ex`:

```elixir
defmodule MyBot.Bot do
  use Lingo.Bot

  command "ping", "Responds with pong" do
    reply!(ctx, "Pong!")
  end
end
```

`use Lingo.Bot` gives you all the macros and helpers. The `command` macro defines a slash command. `ctx` is the interaction context, and `reply!/2` sends a response.

## Start the Bot

Edit `lib/my_bot/application.ex`:

```elixir
defmodule MyBot.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Lingo,
       bot: MyBot.Bot,
       token: System.get_env("BOT_TOKEN"),
       intents: [:guilds, :guild_messages]}
    ]

    {:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one)

    Lingo.register_commands(MyBot.Bot)

    {:ok, pid}
  end
end
```

`register_commands/1` pushes your commands to Discord as global commands. Global commands can take up to an hour to show up. During development, use `register_commands_to_guild/2` instead since guild commands update instantly:

```elixir
Lingo.register_commands_to_guild(MyBot.Bot, "YOUR_GUILD_ID")
```

## Run It

Set your `BOT_TOKEN` environment variable and start the application:

```elixir
mix run --no-halt
```

Type `/ping` in your server and the bot replies with "Pong!".

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `bot` | module | **required** | Bot module with `use Lingo.Bot` |
| `token` | string | **required** | Bot token |
| `intents` | `[atom] \| integer` | `[:guilds, :guild_messages]` | Gateway intents (see [Intents](/gateway/intents)) |
| `cache` | `keyword \| false` | `[]` | Cache config, or `false` to disable (see [Cache](/cache#configuration)) |
| `sharding` | keyword | `[]` | Sharding config (see [Sharding](/gateway/sharding#configuration)) |
| `presence` | keyword | `[]` | Initial presence (see [Presence](/gateway/presence#initial-presence)) |

## Next Steps

- [Commands](/commands): options, subcommands, permissions, context menus
- [Events](/events): reacting to messages, member joins, and other gateway events
- [Interactions](/interactions): buttons, select menus, modals, autocomplete
