defmodule Lingo.Type.OnboardingTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.{Emoji, Onboarding}

  # Discord's example guild onboarding, shortened
  @example ~S"""
  {
    "guild_id": "960007075288915998",
    "prompts": [
      {
        "id": "1067461047608422473",
        "title": "What do you want to do in this community?",
        "options": [
          {
            "id": "1067461047608422476",
            "title": "Chat with Friends",
            "description": "",
            "emoji": {"id": "1070002302032826408", "name": "chat", "animated": false},
            "role_ids": [],
            "channel_ids": ["962007075288916001"]
          },
          {
            "id": "1070004843541954678",
            "title": "Get Gud",
            "description": "We have excellent teachers!",
            "emoji": {"id": null, "name": "😀", "animated": false},
            "role_ids": ["982014491980083211"],
            "channel_ids": []
          }
        ],
        "single_select": false,
        "required": false,
        "in_onboarding": true,
        "type": 0
      }
    ],
    "default_channel_ids": ["998678771706110023", "998678693058719784"],
    "enabled": true
  }
  """

  test "parses Discord's example onboarding" do
    onboarding = Onboarding.new(JSON.decode!(@example))

    assert %Onboarding{
             guild_id: "960007075288915998",
             default_channel_ids: ["998678771706110023", "998678693058719784"],
             enabled: true,
             mode: :default,
             prompts: [prompt]
           } = onboarding

    assert %{
             id: "1067461047608422473",
             type: :multiple_choice,
             single_select: false,
             required: false,
             in_onboarding: true,
             options: [chat, gud]
           } = prompt

    assert %{
             title: "Chat with Friends",
             channel_ids: ["962007075288916001"],
             role_ids: [],
             emoji: %Emoji{id: "1070002302032826408", name: "chat"}
           } = chat

    assert %{role_ids: ["982014491980083211"], emoji: %Emoji{id: nil, name: "😀"}} = gud
  end

  test "maps the mode and prompt types" do
    onboarding =
      Onboarding.new(%{"mode" => 1, "prompts" => [%{"type" => 1, "options" => []}]})

    assert %Onboarding{mode: :advanced, prompts: [%{type: :dropdown, options: []}]} = onboarding
  end
end
