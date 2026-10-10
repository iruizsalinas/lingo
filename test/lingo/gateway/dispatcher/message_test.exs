defmodule Lingo.Gateway.Dispatcher.MessageTest do
  use ExUnit.Case, async: true

  alias Lingo.Gateway.Dispatcher
  alias Lingo.Type.{Member, Message}

  defmodule DispatchBot do
    use Lingo.Bot

    @impl true
    def handle_event(event, data), do: send(Lingo.Instance.get(:test_pid), {event, data})
  end

  setup do
    %{
      bot:
        Lingo.TestBot.start(
          bot: DispatchBot,
          test_pid: self(),
          start: [:cache, :collector],
          cache: [
            guilds: true,
            channels: true,
            roles: true,
            users: true,
            members: true,
            messages: true,
            presences: true
          ]
        )
    }
  end

  test "dispatches message create with channel_type intact" do
    Dispatcher.dispatch(:message_create, %{
      "id" => "message1",
      "channel_id" => "channel1",
      "channel_type" => 0,
      "guild_id" => "guild1",
      "author" => %{"id" => "user1", "username" => "alice", "discriminator" => "0"},
      "member" => %{"nick" => "Alice", "roles" => ["role1"]},
      "content" => "hello",
      "timestamp" => "2026-01-01T00:00:00Z"
    })

    assert_receive {:message_create, %Message{} = message}

    assert message.id == "message1"
    assert message.channel_type == :guild_text
    assert message.guild_id == "guild1"
    assert message.member.guild_id == "guild1"
    assert message.member.user.id == "user1"

    assert %Message{
             channel_type: :guild_text,
             member: %Member{guild_id: "guild1", user: %{id: "user1"}}
           } =
             Lingo.Cache.get_message("channel1", "message1")
  end

  test "dispatches message update with channel_type intact" do
    Dispatcher.dispatch(:message_update, %{
      "id" => "message1",
      "channel_id" => "channel1",
      "channel_type" => 0,
      "guild_id" => "guild1",
      "content" => "edited",
      "timestamp" => "2026-01-01T00:00:00Z"
    })

    assert_receive {:message_update, %{old: nil, new: %Message{} = message}}

    assert message.id == "message1"
    assert message.channel_type == :guild_text
    assert message.guild_id == "guild1"
  end

  test "dispatches message update with merged cached message when update is partial" do
    Dispatcher.dispatch(:message_create, %{
      "id" => "message2",
      "channel_id" => "channel1",
      "channel_type" => 0,
      "guild_id" => "guild1",
      "author" => %{"id" => "user1", "username" => "alice", "discriminator" => "0"},
      "member" => %{"nick" => "Alice", "roles" => ["role1"]},
      "content" => "before",
      "timestamp" => "2026-01-01T00:00:00Z"
    })

    assert_receive {:message_create, %Message{}}

    Dispatcher.dispatch(:message_update, %{
      "id" => "message2",
      "channel_id" => "channel1",
      "content" => "after",
      "member" => %{"nick" => "Edited", "roles" => ["role2"]}
    })

    assert_receive {:message_update, %{old: %Message{content: "before"}, new: %Message{} = new}}

    assert new.content == "after"
    assert new.guild_id == "guild1"
    assert new.channel_type == :guild_text
    assert new.author.id == "user1"
    assert %Member{guild_id: "guild1", nick: "Edited", user: %{id: "user1"}} = new.member
  end
end
