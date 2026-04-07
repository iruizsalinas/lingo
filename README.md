# Lingo

An Elixir library for interacting with the Discord API.

Currently covers:

- Slash commands, context menus, buttons, select menus, modals, and autocomplete
- Components V2 including sections, containers, media galleries, and more
- REST API with per-bucket rate limiting and automatic retries
- Gateway with sharding, caching, and reconnection
- Collectors for awaiting button clicks and reactions
- Permission and role hierarchy helpers
- Embed builder, CDN helpers, and component builders

Check out the [docs](https://iruizsalinas.github.io/lingo/) for guides and the full API reference.

## Install

```elixir
{:lingo, "~> 0.2.1"}
```

## Quick start

```elixir
defmodule MyBot do
  use Lingo.Bot

  command "ping", "Responds with pong" do
    reply!(ctx, "Pong!")
  end

  handle :message_create, msg do
    if msg.content == "hello" do
      Lingo.send_message(msg.channel_id, content: "Hello back!")
    end
  end
end
```

```elixir
children = [
  {Lingo,
   bot: MyBot,
   token: System.get_env("BOT_TOKEN"),
   intents: [:guilds, :guild_messages]}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

Register your slash commands with Discord (run once from `iex`, or after changes):

```elixir
Lingo.register_commands(MyBot)
```

## Commands with options

```elixir
command "greet", "Greet someone",
  options: [
    user("target", "Who to greet", required: true)
  ] do
  user = resolved_user(ctx, option(ctx, "target"))
  reply!(ctx, "Hey #{user.username}!")
end
```

## Components and collectors

```elixir
command "confirm", "Ask for confirmation" do
  reply!(ctx, content: "Are you sure?", components: [
    Lingo.action_row([
      Lingo.button(custom_id: "yes", label: "Yes", style: :success),
      Lingo.button(custom_id: "no", label: "No", style: :danger)
    ])
  ])
end

component "yes", ctx do
  update!(ctx, content: "Confirmed!", components: [])
end
```

Or use collectors to await interactions inline:

```elixir
case Lingo.await_component(msg.id, timeout: 30_000) do
  {:ok, interaction} -> # handle the click
  :timeout -> # no response
end
```

## Embeds

```elixir
Lingo.embed(
  title: "Server Info",
  color: 0x5865F2,
  fields: [
    %{name: "Members", value: "1,234", inline: true},
    %{name: "Created", value: Lingo.timestamp(guild.created_at, :relative), inline: true}
  ]
)
```

## Events

```elixir
handle :guild_member_add, member do
  Lingo.send_message(channel_id,
    content: "Welcome #{Lingo.mention_user(member.user.id)}!"
  )
end

handle :message_update, %{old: old, new: msg} do
  if old, do: IO.puts("Changed from: #{old.content}")
end
```