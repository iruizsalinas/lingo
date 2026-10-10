defmodule Lingo.PollTest do
  use ExUnit.Case, async: true

  alias Lingo.Poll

  test "builds the question and answers, with optional emojis" do
    assert Poll.build("Lunch?", ["Pizza", {"Pasta", "🍝"}, {"Soup", %Lingo.Type.Emoji{id: "9"}}]) ==
             %{
               question: %{text: "Lunch?"},
               answers: [
                 %{poll_media: %{text: "Pizza"}},
                 %{poll_media: %{text: "Pasta", emoji: %{name: "🍝"}}},
                 %{poll_media: %{text: "Soup", emoji: %{id: "9"}}}
               ]
             }
  end

  test "takes duration and multiselect" do
    poll = Poll.build("Q", ["A", "B"], duration: 48, multiselect: true)
    assert poll.duration == 48
    assert poll.allow_multiselect == true
  end
end
