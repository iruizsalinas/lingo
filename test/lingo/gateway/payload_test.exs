defmodule Lingo.Gateway.PayloadTest do
  use ExUnit.Case, async: true

  alias Lingo.Gateway.Payload

  describe "identify/4" do
    test "produces valid identify payload" do
      payload = Payload.identify("token123", 513, 0, 1)

      assert payload["op"] == 2
      assert payload["d"]["token"] == "token123"
      assert payload["d"]["intents"] == 513
      assert payload["d"]["shard"] == [0, 1]
      assert payload["d"]["large_threshold"] == 250
      assert payload["d"]["properties"]["browser"] == "lingo"
    end

    test "shard array reflects shard_id and count" do
      payload = Payload.identify("t", 1, 3, 8)
      assert payload["d"]["shard"] == [3, 8]
    end
  end

  describe "resume/3" do
    test "produces valid resume payload" do
      payload = Payload.resume("token", "session_abc", 42)

      assert payload["op"] == 6
      assert payload["d"]["token"] == "token"
      assert payload["d"]["session_id"] == "session_abc"
      assert payload["d"]["seq"] == 42
    end
  end

  describe "heartbeat/1" do
    test "with sequence number" do
      payload = Payload.heartbeat(17)
      assert payload["op"] == 1
      assert payload["d"] == 17
    end

    test "with nil sequence" do
      payload = Payload.heartbeat(nil)
      assert payload["op"] == 1
      assert payload["d"] == nil
    end
  end

  describe "presence_update/3" do
    test "online with no activity" do
      payload = Payload.presence_update(:online)
      assert payload["op"] == 3
      assert payload["d"]["status"] == "online"
      assert payload["d"]["activities"] == []
      assert payload["d"]["afk"] == false
    end

    test "idle sets afk and since" do
      payload = Payload.presence_update(:idle)
      assert payload["d"]["status"] == "idle"
      assert payload["d"]["afk"] == true
      assert is_integer(payload["d"]["since"])
    end

    test "with text activity" do
      payload = Payload.presence_update(:online, "Playing a game")
      [activity] = payload["d"]["activities"]
      assert activity["name"] == "Playing a game"
      assert activity["type"] == 0
    end
  end

  describe "request_guild_members/2" do
    test "default query" do
      payload = Payload.request_guild_members("guild123")
      assert payload["op"] == 8
      assert payload["d"]["guild_id"] == "guild123"
      assert payload["d"]["query"] == ""
      assert payload["d"]["limit"] == 0
    end

    test "with user_ids" do
      payload = Payload.request_guild_members("g1", user_ids: ["u1", "u2"])
      assert payload["d"]["user_ids"] == ["u1", "u2"]
      refute Map.has_key?(payload["d"], "query")
    end

    test "with query and limit" do
      payload = Payload.request_guild_members("g1", query: "ali", limit: 10)
      assert payload["d"]["query"] == "ali"
      assert payload["d"]["limit"] == 10
    end

    test "with nonce" do
      payload = Payload.request_guild_members("g1", nonce: "abc")
      assert payload["d"]["nonce"] == "abc"
    end
  end

  describe "encode/decode roundtrip" do
    test "json roundtrip preserves data" do
      original = Payload.heartbeat(42)
      encoded = Payload.encode(original)
      decoded = Payload.decode(encoded)
      assert decoded == original
    end
  end
end
