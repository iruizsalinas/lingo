# Lingo

An Elixir library for interacting with the Discord API.

## Install

```elixir
{:lingo, "~> 0.1.0"}
```

## Example

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

defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Lingo,
       bot: MyBot,
       token: System.get_env("BOT_TOKEN"),
       intents: [:guilds, :guild_messages]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

Check out the [docs](https://iruizsalinas.github.io/lingo/) for guides and the full API reference.
