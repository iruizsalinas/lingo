defmodule Lingo.Cache.MessageTest do
  use ExUnit.Case, async: true

  alias Lingo.Cache
  alias Lingo.Cache.Store
  alias Lingo.Type.{Message, User}

  setup do
    %{bot: Lingo.TestBot.start(start: [:cache], cache: [messages: true])}
  end

  defp message(channel_id, id),
    do: %Message{id: id, channel_id: channel_id, content: id, author: %User{id: "u1"}}

  test "gets a message by channel and id" do
    Store.put_message(message("c1", "10"))
    assert Cache.Message.get("c1", "10").content == "10"
    assert Cache.Message.get("c2", "10") == nil
  end

  test "lists a channel's messages, oldest first" do
    for id <- ["30", "100", "20"], do: Store.put_message(message("c1", id))
    Store.put_message(message("c2", "40"))

    assert Enum.map(Cache.Message.list("c1"), & &1.id) == ["20", "30", "100"]
  end
end
