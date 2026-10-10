defmodule Lingo.Type.ActivityTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.Activity

  describe "Activity" do
    test "parses current optional activity fields" do
      activity =
        Activity.new(%{
          "name" => "Competing",
          "type" => 5,
          "url" => "https://example.com/activity",
          "created_at" => 1_765_000_000,
          "timestamps" => %{"start" => 1_765_000_000},
          "application_id" => "app1",
          "status_display_type" => 1,
          "details" => "Ranked",
          "details_url" => "https://example.com/details",
          "state" => "Queue",
          "state_url" => "https://example.com/state",
          "emoji" => %{"name" => "wave"},
          "party" => %{"id" => "party1", "size" => [1, 5]},
          "assets" => %{"large_image" => "asset1"},
          "secrets" => %{"join" => "secret"},
          "instance" => true,
          "flags" => 1,
          "buttons" => [%{"label" => "Join", "url" => "https://example.com/join"}]
        })

      assert activity.type == :competing
      assert activity.timestamps["start"] == 1_765_000_000
      assert activity.status_display_type == 1
      assert activity.details_url == "https://example.com/details"
      assert activity.state_url == "https://example.com/state"
      assert activity.emoji["name"] == "wave"
      assert activity.party["id"] == "party1"
      assert activity.assets["large_image"] == "asset1"
      assert activity.secrets["join"] == "secret"
      assert activity.instance == true
      assert activity.flags == 1
      assert [%{"label" => "Join"}] = activity.buttons
    end
  end

  describe "Activity payloads" do
    test "custom status keeps its state text" do
      payload = Activity.to_payload(%Activity{name: "Custom Status", type: :custom, state: "Hi"})
      assert payload == %{"name" => "Custom Status", "type" => 4, "state" => "Hi"}
    end
  end
end
