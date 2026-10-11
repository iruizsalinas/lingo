defmodule Lingo.Type.PollTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.{Emoji, Poll}

  test "parses a poll with its answers and results" do
    poll =
      Poll.new(%{
        "question" => %{"text" => "Pizza or pasta?"},
        "answers" => [
          %{"answer_id" => 1, "poll_media" => %{"text" => "Pizza"}},
          %{
            "answer_id" => 2,
            "poll_media" => %{"text" => "Pasta", "emoji" => %{"id" => nil, "name" => "🍝"}}
          }
        ],
        "expiry" => "2026-10-12T12:00:00.000000+00:00",
        "allow_multiselect" => false,
        "layout_type" => 1,
        "results" => %{
          "is_finalized" => false,
          "answer_counts" => [%{"id" => 2, "count" => 3, "me_voted" => true}]
        }
      })

    assert %Poll{
             question: %{text: "Pizza or pasta?", emoji: nil},
             expiry: ~U[2026-10-12 12:00:00.000000Z],
             allow_multiselect: false,
             layout_type: :default,
             results: %{
               is_finalized: false,
               answer_counts: [%{id: 2, count: 3, me_voted: true}]
             }
           } = poll

    assert [
             %{answer_id: 1, poll_media: %{text: "Pizza", emoji: nil}},
             %{answer_id: 2, poll_media: %{text: "Pasta", emoji: %Emoji{name: "🍝"}}}
           ] = poll.answers
  end

  test "a poll without results or expiry, as in a non-expiring poll" do
    assert %Poll{results: nil, expiry: nil, answers: []} =
             Poll.new(%{"question" => %{"text" => "?"}, "expiry" => nil})
  end
end
