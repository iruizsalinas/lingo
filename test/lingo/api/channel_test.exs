defmodule Lingo.Api.ChannelTest do
  use ExUnit.Case, async: true

  import Lingo.FakeRest, only: [respond: 1]

  alias Lingo.Api.Channel
  alias Lingo.Type.Message

  setup do
    Lingo.FakeRest.start()
    :ok
  end

  test "following an announcement channel returns the followed channel" do
    respond(%{"channel_id" => "c1", "webhook_id" => "w1"})

    assert {:ok, %{channel_id: "c1", webhook_id: "w1"}} =
             Channel.follow_announcement("c1", "c2")

    assert_received {:request, :post, "/api/v10/channels/c1/followers", [],
                     %{"webhook_channel_id" => "c2"}}
  end

  test "pins carry when they were pinned, which pages through the rest" do
    respond(%{
      "items" => [
        %{
          "pinned_at" => "2026-10-01T12:00:00.000000+00:00",
          "message" => %{"id" => "m1", "channel_id" => "c1"}
        }
      ],
      "has_more" => true
    })

    assert {:ok, %{items: [pin], has_more: true}} = Channel.list_pins("c1", limit: 1)
    assert %{pinned_at: ~U[2026-10-01 12:00:00.000000Z], message: %Message{id: "m1"}} = pin
    assert_received {:request, :get, "/api/v10/channels/c1/messages/pins", [{"limit", "1"}], nil}

    assert {:ok, _} = Channel.list_pins("c1", before: pin.pinned_at)

    assert_received {:request, :get, "/api/v10/channels/c1/messages/pins",
                     [{"before", "2026-10-01T12:00:00.000000Z"}], nil}
  end
end
