# Lingo

An Elixir library for interacting with the Discord API.

Currently covers:

- Slash commands, context menus, buttons, select menus, modals, and autocomplete
- Components V2 including sections, containers, media galleries, and more
- REST API with per-bucket rate limiting and automatic retries
- Gateway with sharding, caching, and reconnection: resumable sessions, zero-downtime resharding, shards (and cache reads) across nodes, ETF and zstd
- Interactions and webhook events over HTTP, with or without a gateway
- Command checks, cooldowns and an error callback
- OAuth2, and test helpers for bots
- Voice: play and receive audio, with Discord's end-to-end encryption (DAVE)
- Several bots in one VM, each with its own cache, rate limits and gateway
- Collectors for awaiting button clicks and reactions
- Permission and role hierarchy helpers
- Embed builder, CDN helpers, and component builders

No runtime dependencies: just OTP and Elixir 1.18+.

Check out the [docs](https://hexdocs.pm/lingo/) for the API reference.

## Install

```elixir
{:lingo, "~> 0.3.0"}
```

## Quick start

A bot is a module that declares its commands and implements the `Lingo.Bot`
callbacks it needs:

```elixir
defmodule MyBot do
  use Lingo.Bot

  command "ping", "Responds with pong"

  @impl true
  def handle_command("ping", ctx), do: reply!(ctx, "Pong!")

  @impl true
  def handle_event(:message_create, %{content: "hello"} = msg) do
    Lingo.Api.Message.create(msg.channel_id, "Hello back!")
  end
end
```

Add it to your supervision tree:

```elixir
children = [
  {MyBot,
   token: System.fetch_env!("BOT_TOKEN"),
   intents: [:guilds, :guild_messages, :message_content],
   register_commands: :global}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

`register_commands: :global` sends your commands to Discord once the bot is
ready. During development, `{:guild, guild_id}` updates instantly instead. You
can also call `Lingo.register_commands/1` yourself.

## Where things are

| Module | What it does |
|--------|--------------|
| `Lingo` | Starting bots, picking one, registering commands |
| `Lingo.Bot` | The behaviour your bot module implements |
| `Lingo.Context` | The interaction a callback handles: reading it and replying |
| `Lingo.Api.*` | The REST API, one module per resource (`Lingo.Api.Message`, `Lingo.Api.Guild`...) |
| `Lingo.Cache.*` | What the gateway and REST API have told the bot, one module per resource (`Lingo.Cache.Role.list/1`...); opt-in, configured in `Lingo.Cache` |
| `Lingo.Gateway` | Presence, shards and gateway requests |
| `Lingo.Voice` | Joining voice channels, playing and receiving audio |
| `Lingo.Component`, `Lingo.Embed` | Building message content |
| `Lingo.Collector` | Awaiting clicks and reactions inline |
| `Lingo.Endpoint` | Interactions and webhook events over HTTP |
| `Lingo.OAuth2` | Authorizing users and calling the API as them |
| `Lingo.Testing` | Testing a bot without Discord |
| `Lingo.Telemetry` | Events for metrics |
| `Lingo.Helper.*`, `Lingo.Permissions`, `Lingo.Format`, `Lingo.CDN` | Utilities |

## Commands with options

```elixir
command "greet", "Greet someone",
  options: [
    user(:target, "Who to greet", required: true),
    string(:message, "What to say")
  ]

@impl true
def handle_command("greet", ctx) do
  user = get_user(ctx, :target)
  reply!(ctx, "#{option(ctx, :message) || "Hey"} #{user.username}!")
end
```

Every callback is an ordinary function, so you match on whatever you like and
everything else is ignored.

## Components and collectors

```elixir
command "confirm", "Ask for confirmation"

@impl true
def handle_command("confirm", ctx) do
  reply!(ctx,
    content: "Are you sure?",
    components: [
      Lingo.Component.action_row([
        Lingo.Component.button(custom_id: "confirm:yes", label: "Yes", style: :success),
        Lingo.Component.button(custom_id: "confirm:no", label: "No", style: :danger)
      ])
    ]
  )
end

@impl true
def handle_component("confirm:" <> answer, ctx) do
  update!(ctx, content: "You said #{answer}.", components: [])
end
```

Or use collectors to await interactions inline:

```elixir
case Lingo.Collector.await_component(msg.id, timeout: 30_000) do
  {:ok, interaction} -> # handle the click
  :timeout -> # no response
end
```

## Events

```elixir
@impl true
def handle_event(:guild_member_add, member) do
  Lingo.Api.Message.create(welcome_channel_id, "Welcome #{Lingo.Format.mention_user(member.user.id)}!")
end

def handle_event(:message_update, %{old: %{content: old}, new: msg}) do
  IO.puts("#{msg.author.username} changed #{inspect(old)} to #{inspect(msg.content)}")
end
```

## Errors

API calls return `{:ok, result}`, `:ok` or `{:error, %Lingo.Error{}}`, and the
`!` helpers raise `Lingo.Error`:

```elixir
case Lingo.Api.Message.get(channel_id, message_id) do
  {:ok, message} -> message
  {:error, %Lingo.Error{status: 404}} -> nil
end
```

## Embeds

```elixir
Lingo.Embed.build(
  title: "Server Info",
  color: 0x5865F2,
  fields: [
    %{name: "Members", value: "1,234", inline: true},
    %{name: "Joined", value: Lingo.Format.timestamp(member.joined_at, :relative), inline: true}
  ]
)
```
