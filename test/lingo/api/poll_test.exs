defmodule Lingo.Api.PollTest do
  use ExUnit.Case, async: true

  import Lingo.FakeRest, only: [respond: 1]

  alias Lingo.Api.Poll
  alias Lingo.Type.{Message, User}

  setup do
    Lingo.FakeRest.start()
    :ok
  end

  test "an answer's voters are users" do
    respond(%{"users" => [%{"id" => "u1", "username" => "a"}]})

    assert {:ok, [%User{id: "u1", username: "a"}]} =
             Poll.list_answer_voters("c1", "m1", 2, after: "u0", limit: 10)

    assert_received {:request, :get, "/api/v10/channels/c1/polls/m1/answers/2", query, nil}
    assert Enum.sort(query) == [{"after", "u0"}, {"limit", "10"}]
  end

  test "ending a poll returns its message" do
    respond(%{"id" => "m1", "channel_id" => "c1", "poll" => %{"question" => %{"text" => "?"}}})

    assert {:ok, %Message{id: "m1", poll: %Lingo.Type.Poll{question: %{text: "?"}}}} =
             Poll.expire("c1", "m1")

    assert_received {:request, :post, "/api/v10/channels/c1/polls/m1/expire", [], nil}
  end
end
