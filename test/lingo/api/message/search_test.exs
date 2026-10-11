defmodule Lingo.Api.Message.SearchTest do
  use ExUnit.Case, async: true

  import Lingo.FakeRest, only: [respond: 1, respond: 2]

  alias Lingo.Api.Message
  alias Lingo.Type.{Channel, ThreadMember}

  setup do
    Lingo.FakeRest.start()
    :ok
  end

  test "results come back parsed, with list options as repeated keys" do
    respond(%{
      "doing_deep_historical_index" => false,
      "total_results" => 1,
      "messages" => [[%{"id" => "m1", "channel_id" => "t1", "content" => "hi"}]],
      "threads" => [%{"id" => "t1", "type" => 11}],
      "members" => [%{"id" => "t1", "user_id" => "bot", "flags" => 0}]
    })

    assert {:ok, result} =
             Message.search("g1", content: "hi", author_id: ["u1", "u2"], limit: 5)

    assert %{
             doing_deep_historical_index: false,
             documents_indexed: nil,
             total_results: 1,
             messages: [[%Lingo.Type.Message{id: "m1", content: "hi"}]],
             threads: [%Channel{id: "t1", type: :public_thread}],
             members: [%ThreadMember{id: "t1", user_id: "bot"}]
           } = result

    assert_received {:request, :get, "/api/v10/guilds/g1/messages/search", query, nil}

    assert Enum.sort(query) == [
             {"author_id", "u1"},
             {"author_id", "u2"},
             {"content", "hi"},
             {"limit", "5"}
           ]
  end

  test "an index Discord is still building is retried, then reported" do
    respond(202, %{"code" => 110_000, "retry_after" => 0})

    assert {:error, %Lingo.Error{reason: :index_not_ready}} =
             Message.search("g1", search_index_retries: 1, search_index_short_delay: 0)

    assert_received {:request, :get, "/api/v10/guilds/g1/messages/search", [], nil}
    assert_received {:request, :get, "/api/v10/guilds/g1/messages/search", [], nil}
    refute_received {:request, _, _, _, _}
  end
end
