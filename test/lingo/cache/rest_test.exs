defmodule Lingo.Cache.RestTest do
  use ExUnit.Case, async: true
  alias Lingo.Cache
  alias Lingo.Cache.{Rest, Store, Tables}
  alias Lingo.Rest.Client
  alias Lingo.Type.{Channel, Guild, Member, Message, Role, User, VoiceState}

  defp start(cache, handler) do
    Lingo.TestBot.start(
      start: [:cache, :rate_limiter],
      cache: cache,
      user_id: "me",
      http_request: fn method, url, _, body ->
        {status, data} = handler.(method, URI.parse(url).path, body)

        {:ok,
         %{
           status: status,
           headers: [{"content-type", "application/json"}],
           body: if(status == 204, do: "", else: JSON.encode!(data))
         }}
      end
    )
  end

  test "complete role lists refresh values, prune missing roles and isolate guilds" do
    start([roles: true], fn _, _, _ -> {200, [%{"id" => "r", "name" => "new"}]} end)
    Store.put_role("g", %Role{id: "r", name: "old", guild_id: "g"})
    Store.put_role("g", %Role{id: "gone"})
    Store.put_role("other", %Role{id: "gone"})
    assert {:ok, [%Role{name: "new"}]} = Lingo.Api.Role.list("g")
    assert Cache.get_role("g", "r").name == "new"
    assert Cache.get_role("g", "gone") == nil
    assert Cache.get_role("other", "gone") != nil
    assert Cache.stats().roles.entries == 2
  end

  test "empty authoritative lists remove kept roles and leave indexes consistent" do
    start([roles: [max_entries: 1, ttl: 10_000, keep: :all]], fn _, _, _ -> {200, []} end)
    Store.put_role("g", %Role{id: "r"})
    assert {:ok, []} = Lingo.Api.Role.list("g")
    assert Cache.list_roles("g") == []
    assert Cache.stats().roles.kept == 0
    assert :ets.info(Tables.resource(:roles).meta, :size) == 0
  end

  test "a gateway update during a request wins over its REST response and reconciliation" do
    start([roles: true], fn _, _, _ ->
      Store.put_role("g", %Role{id: "r", name: "gateway"})
      Store.put_role("g", %Role{id: "new"})
      {200, [%{"id" => "r", "name" => "rest"}]}
    end)

    assert {:ok, [%Role{name: "rest"}]} = Lingo.Api.Role.list("g")
    assert Cache.get_role("g", "r").name == "gateway"
    assert Cache.get_role("g", "new") != nil
  end

  test "deleting an absent entry or clearing while a request runs prevents resurrection" do
    for mutation <- [fn -> Store.delete_role("g", "r") end, fn -> Cache.clear(:roles) end] do
      start([roles: true], fn _, _, _ ->
        mutation.()
        {200, %{"id" => "r"}}
      end)

      assert {:ok, %Role{}} = Lingo.Api.Role.get("g", "r")
      assert Cache.get_role("g", "r") == nil
    end
  end

  test "a newer REST completion cannot be overwritten by an older snapshot" do
    start([roles: true], fn _, _, _ -> {200, %{}} end)
    older = Rest.begin(:get, "/guilds/g/roles/r", [])
    newer = Rest.begin(:get, "/guilds/g/roles/r", [])
    assert {:ok, _} = Rest.finish(newer, {:ok, %{"id" => "r", "name" => "new"}})
    assert {:ok, _} = Rest.finish(older, {:ok, %{"id" => "r", "name" => "old"}})
    assert Cache.get_role("g", "r").name == "new"
  end

  test "failed requests leave existing cache data intact" do
    start([roles: true], fn _, _, _ -> {403, %{"message" => "denied", "code" => 50013}} end)
    Store.put_role("g", %Role{id: "r", name: "old"})
    assert {:error, _} = Lingo.Api.Role.delete("g", "r")
    assert Cache.get_role("g", "r").name == "old"
  end

  test "REST writes honor filters, keep, limits, compression and TTL" do
    start(
      [
        roles: [
          max_entries: 1,
          ttl: 10,
          compressed: true,
          filter: fn role, _ -> role.name != "reject" end,
          keep: fn role, _ -> role.id == "kept" end
        ]
      ],
      fn _, _, _ ->
        {200,
         [
           %{"id" => "kept", "name" => "reject"},
           %{"id" => "reject", "name" => "reject"},
           %{"id" => "ordinary", "name" => "accepted"}
         ]}
      end
    )

    assert {:ok, roles} = Lingo.Api.Role.list("g")
    assert length(roles) == 3
    assert Cache.get_role("g", "kept") != nil
    assert Cache.get_role("g", "reject") == nil
    assert Cache.get_role("g", "ordinary") == nil
    assert Cache.stats().roles.kept == 1
    assert :ets.info(Tables.table(:roles), :compressed)
    Process.sleep(15)
    assert Cache.get_role("g", "kept") != nil
  end

  test "members and embedded users are independent, pages never prune" do
    start([members: true, users: false], fn _, _, _ ->
      {200, [%{"user" => %{"id" => "u", "username" => "alice"}, "roles" => ["r"]}]}
    end)

    Store.put_member("g", %Member{user: %User{id: "other"}})
    assert {:ok, [_]} = Lingo.Api.Member.list("g")
    assert Cache.get_member("g", "u").user.username == "alice"
    assert Cache.get_member("g", "other") != nil
    assert Cache.get_user("u") == nil
  end

  test "partial guild and member responses preserve gateway-only and omitted fields" do
    start([guilds: true, members: true], fn _, path, _ ->
      if String.ends_with?(path, "/guilds/g"),
        do: {200, %{"id" => "g", "name" => "new"}},
        else: {200, %{"nick" => nil, "roles" => []}}
    end)

    Store.put_guild(%Guild{id: "g", joined_at: ~U[2026-10-10 12:00:00Z], member_count: 7})

    Store.put_member("g", %Member{
      user: %User{id: "u", username: "alice", bot: true},
      nick: "old",
      roles: ["r"]
    })

    assert {:ok, _} = Lingo.Api.Guild.get("g")
    assert Cache.get_guild("g").member_count == 7
    assert Cache.get_guild("g").joined_at == ~U[2026-10-10 12:00:00Z]
    assert {:ok, _} = Lingo.Api.Member.update("g", "u", %{nick: nil})
    assert Cache.get_member("g", "u").nick == nil
    assert Cache.get_member("g", "u").roles == []
    assert Cache.get_member("g", "u").user.username == "alice"
  end

  test "message and channel deletion invalidate descendants" do
    start([channels: true, messages: true], fn _, _, _ -> {200, %{"id" => "c"}} end)
    Store.put_channel(%Channel{id: "c"})
    Store.put_message(%Message{id: "m", channel_id: "c"})
    assert {:ok, _} = Lingo.Api.Channel.delete("c")
    assert Cache.get_channel("c") == nil
    assert Cache.get_message("c", "m") == nil
  end

  test "bulk deletions, role changes and voice state responses update only relevant caches" do
    start([messages: true, members: true, voice_states: true], fn method, _, _ ->
      if method == :get,
        do: {200, %{"user_id" => "u", "channel_id" => "v"}},
        else: {204, nil}
    end)

    Store.put_message(%Message{id: "a", channel_id: "c"})
    Store.put_message(%Message{id: "b", channel_id: "c"})
    Store.put_member("g", %Member{user: %User{id: "u"}, roles: []})
    assert :ok = Lingo.Api.Message.bulk_delete("c", ["a", "b"])
    assert Cache.get_message("c", "a") == nil
    assert Cache.get_message("c", "b") == nil
    assert :ok = Lingo.Api.Member.add_role("g", "u", "r")
    assert Cache.get_member("g", "u") == nil
    assert {:ok, _} = Lingo.Api.Voice.get_user_voice_state("g", "u")
    assert %VoiceState{channel_id: "v"} = Cache.get_voice_state("g", "u")
  end

  test "disabled caches skip route classification and response traversal" do
    start(false, fn _, _, _ -> {200, []} end)
    assert Rest.begin(:get, :not_a_path, :invalid_options) == nil
    assert Rest.finish(nil, {:ok, :not_a_payload}) == {:ok, :not_a_payload}
    assert {:ok, []} = Lingo.Api.Role.list("g")
    assert Cache.stats().roles.memory_bytes == 0

    start([users: true], fn _, _, _ -> {200, []} end)
    assert Rest.begin(:get, "/guilds/g/roles", []) == nil

    assert Rest.begin(:post, "/channels/c/messages/bulk-delete",
             json: %{messages: :not_enumerable}
           ) == nil
  end

  test "successful role creates, edits, position changes and deletes synchronize" do
    start([roles: true], fn method, path, _ ->
      cond do
        method == :delete ->
          {204, nil}

        method == :patch and String.ends_with?(path, "/roles") ->
          {200, [%{"id" => "r", "position" => 4}]}

        true ->
          {200, %{"id" => "r", "name" => "updated"}}
      end
    end)

    assert {:ok, _} = Lingo.Api.Role.create("g", %{name: "updated"})
    assert Cache.get_role("g", "r").name == "updated"
    assert {:ok, _} = Lingo.Api.Role.update("g", "r", %{name: "updated"})
    assert {:ok, _} = Lingo.Api.Role.update_positions("g", [%{id: "r", position: 4}])
    assert Cache.get_role("g", "r").position == 4
    assert Cache.get_role("g", "r").name == "updated"
    assert :ok = Lingo.Api.Role.delete("g", "r")
    assert Cache.get_role("g", "r") == nil
  end

  test "pins, threads and channel pages refresh entries without pruning unrelated data" do
    start([messages: true, channels: true, users: true], fn _, path, _ ->
      cond do
        String.ends_with?(path, "/pins") ->
          {200, %{"items" => [%{"message" => %{"id" => "m", "content" => "pin"}}]}}

        String.ends_with?(path, "/active") ->
          {200, %{"threads" => [%{"id" => "t", "type" => 11}]}}

        true ->
          {200, [%{"id" => "c", "name" => "new"}]}
      end
    end)

    Store.put_channel(%Channel{id: "other", guild_id: "g"})
    Store.put_message(%Message{id: "other", channel_id: "c"})
    assert {:ok, _} = Lingo.Api.Channel.list_pins("c")
    assert Cache.get_message("c", "m").content == "pin"
    assert Cache.get_message("c", "pins") == nil
    assert Cache.get_message("c", "other") != nil
    assert {:ok, _} = Lingo.Api.Guild.list_active_threads("g")
    assert Cache.get_channel("t").guild_id == "g"
    assert {:ok, _} = Lingo.Api.Guild.list_channels("g")
    assert Cache.get_channel("c").name == "new"
    assert Cache.get_channel("t") != nil
    assert Cache.get_channel("other") != nil
  end

  test "embedded users refresh even when their parent resource is disabled" do
    start([users: :self], fn _, _, _ ->
      {200,
       [
         %{"id" => "m", "author" => %{"id" => "me", "username" => "bot"}},
         %{"id" => "n", "author" => %{"id" => "other", "username" => "other"}}
       ]}
    end)

    assert {:ok, _} = Lingo.Api.Message.list("c")
    assert Cache.get_user("me").username == "bot"
    assert Cache.get_user("other") == nil
    assert Tables.resource(:messages) == nil
  end

  test "cache restart invalidates outstanding snapshots" do
    bot = start([roles: true], fn _, _, _ -> {200, %{}} end)
    snapshot = Rest.begin(:get, "/guilds/g/roles/r", [])
    stop_supervised!({Tables, bot})
    start_supervised!({Tables, bot: bot, config: [roles: true]})
    assert {:ok, _} = Rest.finish(snapshot, {:ok, %{"id" => "r"}})
    assert Cache.get_role("g", "r") == nil
  end

  test "an unrelated enabled cache does not make disabled-role requests call the owner" do
    start([users: true], fn _, _, _ -> {200, []} end)
    owner = Lingo.Instance.process_name(Tables)
    :sys.suspend(owner)

    try do
      assert {:ok, []} = Lingo.Api.Role.list("g")
    after
      :sys.resume(owner)
    end
  end

  test "partial summaries and role member counts never create full resource records" do
    start([guilds: true, roles: true], fn _, _, _ -> {200, %{"r" => 4}} end)
    assert {:ok, _} = Client.request(:get, "/guilds/g/roles/member-counts")
    assert Cache.list_roles("g") == []
    assert {:ok, _} = Client.request(:get, "/guilds/g/preview")
    assert Cache.get_guild("g") == nil
  end
end
