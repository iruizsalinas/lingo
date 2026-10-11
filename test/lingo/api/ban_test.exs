defmodule Lingo.Api.BanTest do
  use ExUnit.Case, async: true

  import Lingo.FakeRest, only: [respond: 1]

  setup do
    Lingo.FakeRest.start()
    :ok
  end

  test "bulk bans report who was banned and who wasn't" do
    respond(%{"banned_users" => ["u1"], "failed_users" => ["u2"]})

    assert {:ok, %{banned_users: ["u1"], failed_users: ["u2"]}} =
             Lingo.Api.Ban.bulk_create("g1", ["u1", "u2"], delete_message_seconds: 60)

    assert_received {:request, :post, "/api/v10/guilds/g1/bulk-ban", [],
                     %{"user_ids" => ["u1", "u2"], "delete_message_seconds" => 60}}
  end
end
