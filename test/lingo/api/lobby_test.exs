defmodule Lingo.Api.LobbyTest do
  use ExUnit.Case, async: true

  alias Lingo.Api.Lobby

  @base "https://discord.com/api/v10"

  setup do
    Lingo.TestBot.start(start: [:rate_limiter])
    test_pid = self()

    Lingo.Instance.put(Lingo.Instance.current(), :http_request, fn method, url, _headers, body ->
      json =
        if body == nil, do: nil, else: body |> elem(1) |> IO.iodata_to_binary() |> JSON.decode!()

      send(test_pid, {:request, method, url, json})
      {:ok, %{status: 200, headers: [{"content-type", "application/json"}], body: ~s({"id":"1"})}}
    end)

    :ok
  end

  test "each endpoint uses Discord's method, path and body" do
    calls = [
      {fn -> Lobby.create(metadata: %{"mode" => "duo"}) end, :post, "/lobbies",
       %{"metadata" => %{"mode" => "duo"}}},
      {fn -> Lobby.get("1") end, :get, "/lobbies/1", nil},
      {fn -> Lobby.update("1", idle_timeout_seconds: 60) end, :patch, "/lobbies/1",
       %{"idle_timeout_seconds" => 60}},
      {fn -> Lobby.delete("1") end, :delete, "/lobbies/1", nil},
      {fn -> Lobby.update_member("1", "2", flags: 1) end, :put, "/lobbies/1/members/2",
       %{"flags" => 1}},
      {fn -> Lobby.update_members("1", [%{id: "2", remove_member: true}]) end, :post,
       "/lobbies/1/members/bulk", [%{"id" => "2", "remove_member" => true}]},
      {fn -> Lobby.delete_member("1", "2") end, :delete, "/lobbies/1/members/2", nil},
      {fn -> Lobby.create_invite("1", "2") end, :post, "/lobbies/1/members/2/invites", nil},
      {fn -> Lobby.update_moderation_metadata("1", "3", %{"score" => "0.9"}) end, :put,
       "/lobbies/1/messages/3/moderation-metadata", %{"score" => "0.9"}}
    ]

    for {call, method, path, body} <- calls do
      assert {:ok, _} = call.()
      url = @base <> path
      assert_received {:request, ^method, ^url, ^body}
    end
  end

  test "attachments know whether they're spoilers" do
    assert Lingo.Type.Attachment.spoiler?(Lingo.Type.Attachment.new(%{"id" => "1", "flags" => 8}))

    refute Lingo.Type.Attachment.spoiler?(
             Lingo.Type.Attachment.new(%{"id" => "1", "flags" => 32})
           )
  end
end
