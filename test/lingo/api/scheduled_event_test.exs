defmodule Lingo.Api.ScheduledEventTest do
  use ExUnit.Case, async: true

  import Lingo.FakeRest, only: [respond: 1]

  alias Lingo.Type.{Member, User}

  setup do
    Lingo.FakeRest.start()
    :ok
  end

  test "interested users come with their member when asked for" do
    respond([
      %{
        "guild_scheduled_event_id" => "e1",
        "user" => %{"id" => "u1"},
        "member" => %{"nick" => "Ann", "roles" => []}
      },
      %{"guild_scheduled_event_id" => "e1", "user" => %{"id" => "u2"}}
    ])

    assert {:ok, [first, second]} =
             Lingo.Api.ScheduledEvent.list_users("g1", "e1", with_member: true, limit: 2)

    assert %{
             guild_scheduled_event_id: "e1",
             user: %User{id: "u1"},
             member: %Member{nick: "Ann", guild_id: "g1"}
           } = first

    assert %{user: %User{id: "u2"}, member: nil} = second

    assert_received {:request, :get, "/api/v10/guilds/g1/scheduled-events/e1/users", query, nil}
    assert Enum.sort(query) == [{"limit", "2"}, {"with_member", "true"}]
  end
end
