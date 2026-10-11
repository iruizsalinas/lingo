defmodule Lingo.Api.InteractionTest do
  use ExUnit.Case, async: true

  import Lingo.FakeRest, only: [respond: 1, respond: 2]

  alias Lingo.Api.Interaction
  alias Lingo.Type.Message

  setup do
    Lingo.FakeRest.start(start: [:rate_limiter, :pending])
    :ok
  end

  test "a response is :ok when Discord sends nothing back" do
    respond(204, nil)
    assert :ok = Interaction.create_response("i1", "tok", :deferred_channel_message)

    assert_received {:request, :post, "/api/v10/interactions/i1/tok/callback", [], %{"type" => 5}}
  end

  test "with_response returns what the response did" do
    respond(%{
      "interaction" => %{
        "id" => "i1",
        "type" => 2,
        "response_message_id" => "m1",
        "response_message_loading" => false,
        "response_message_ephemeral" => true
      },
      "resource" => %{"type" => 4, "message" => %{"id" => "m1", "content" => "hi"}}
    })

    assert {:ok, %{interaction: interaction, resource: resource}} =
             Interaction.create_response("i1", "tok", :channel_message, %{content: "hi"},
               with_response: true
             )

    assert interaction == %{
             id: "i1",
             type: :application_command,
             activity_instance_id: nil,
             response_message_id: "m1",
             response_message_loading: false,
             response_message_ephemeral: true
           }

    assert %{type: :channel_message, activity_instance: nil, message: %Message{id: "m1"}} =
             resource

    assert_received {:request, :post, "/api/v10/interactions/i1/tok/callback",
                     [{"with_response", "true"}], %{"type" => 4, "data" => %{"content" => "hi"}}}
  end

  test "a launched activity is its instance" do
    respond(%{
      "interaction" => %{"id" => "i1", "type" => 2, "activity_instance_id" => "i-1"},
      "resource" => %{"type" => 12, "activity_instance" => %{"id" => "i-1"}}
    })

    assert {:ok, %{resource: %{type: :launch_activity, activity_instance: %{id: "i-1"}}}} =
             Interaction.create_response("i1", "tok", :launch_activity, nil, with_response: true)
  end
end
