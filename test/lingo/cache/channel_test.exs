defmodule Lingo.Cache.ChannelTest do
  use ExUnit.Case, async: true

  alias Lingo.Cache
  alias Lingo.Cache.Store
  alias Lingo.Type.Channel

  setup do
    %{bot: Lingo.TestBot.start(start: [:cache], cache: [channels: true])}
  end

  test "stores and retrieves a channel" do
    Store.put_channel(%Channel{id: "ch1", name: "general", type: :guild_text, guild_id: "g1"})
    assert %Channel{name: "general", guild_id: "g1"} = Cache.Channel.get("ch1")
  end

  test "deletes a channel" do
    Store.put_channel(%Channel{id: "ch2", name: "voice", type: :guild_voice})
    Store.delete_channel("ch2")
    assert Cache.Channel.get("ch2") == nil
  end
end
