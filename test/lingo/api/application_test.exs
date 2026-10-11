defmodule Lingo.Api.ApplicationTest do
  use ExUnit.Case, async: true

  import Lingo.FakeRest, only: [respond: 1]

  alias Lingo.Api.Application, as: Api
  alias Lingo.Type.{ActivityInstance, Application, RoleConnectionMetadata}

  setup do
    Lingo.FakeRest.start(application_id: "app")
    :ok
  end

  test "the bot's application comes back parsed" do
    respond(%{"id" => "app", "name" => "Bot", "team" => nil, "event_webhooks_status" => 2})

    assert {:ok, %Application{id: "app", name: "Bot", team: nil, event_webhooks_status: :enabled}} =
             Api.get_current()

    assert_received {:request, :get, "/api/v10/applications/@me", [], nil}

    assert {:ok, %Application{}} = Api.update_current(description: "Hi")

    assert_received {:request, :patch, "/api/v10/applications/@me", [], %{"description" => "Hi"}}
  end

  test "activity instances" do
    respond(%{"instance_id" => "i-1", "location" => %{"kind" => "gc"}, "users" => ["1"]})

    assert {:ok, %ActivityInstance{instance_id: "i-1", users: ["1"]}} =
             Api.get_activity_instance("i-1")

    assert_received {:request, :get, "/api/v10/applications/app/activity-instances/i-1", [], nil}
  end

  test "role connection metadata records go up as a list and come back parsed" do
    record = %{"type" => 7, "key" => "verified", "name" => "Verified", "description" => "Is it"}
    respond([record])

    assert {:ok, [%RoleConnectionMetadata{type: :boolean_equal, key: "verified"}]} =
             Api.get_role_connection_metadata()

    assert_received {:request, :get, "/api/v10/applications/app/role-connections/metadata", [],
                     nil}

    assert {:ok, [%RoleConnectionMetadata{}]} =
             Api.update_role_connection_metadata([
               [type: 7, key: "verified", name: "Verified", description: "Is it"]
             ])

    assert_received {:request, :put, "/api/v10/applications/app/role-connections/metadata", [],
                     [^record]}
  end
end
