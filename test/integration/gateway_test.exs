defmodule Lingo.Integration.GatewayTest do
  @moduledoc false
  use Lingo.IntegrationCase

  alias Lingo.Gateway.{Compression, Intents, Payload, WebSocket}

  # /gateway/bot has a tight rate limit, so ask once for the whole module
  setup_all do
    headers = [
      {"authorization", "Bot #{Lingo.Instance.get(:token)}"},
      {"user-agent", "DiscordBot (https://github.com/iruizsalinas/lingo, 0.4.0)"}
    ]

    {:ok, %{status: 200, body: body}} =
      Lingo.Rest.HTTP.request(:get, "https://discord.com/api/v10/gateway/bot", headers)

    %{gateway_url: JSON.decode!(body)["url"]}
  end

  defp connect(gateway_url, query) do
    {:ok, ws} = WebSocket.connect("#{gateway_url}/?#{query}")
    :ok = WebSocket.activate(ws)
    on_exit(fn -> WebSocket.close(ws) end)
    ws
  end

  # feeds socket messages to the client until frames arrive
  defp next_frames(ws, timeout \\ 10_000) do
    receive do
      message ->
        case WebSocket.stream(ws, message) do
          {:ok, ws, []} -> next_frames(ws, timeout)
          {:ok, ws, frames} -> {ws, frames}
        end
    after
      timeout -> flunk("no frame from the gateway")
    end
  end

  describe "gateway handshake" do
    test "connects to gateway and receives Hello (op 10)", %{gateway_url: url} do
      ws = connect(url, "v=10&encoding=json")

      assert {_ws, [{:text, hello_json}]} = next_frames(ws)

      hello = JSON.decode!(hello_json)
      assert hello["op"] == 10
      assert is_integer(hello["d"]["heartbeat_interval"])
      assert hello["d"]["heartbeat_interval"] > 0
    end
  end

  describe "zlib-stream gateway connection" do
    test "connects with zlib compression and receives decompressable Hello", %{gateway_url: url} do
      ws = connect(url, "v=10&encoding=json&compress=zlib-stream")

      assert {_ws, [{:binary, compressed}]} = next_frames(ws)

      ctx = Compression.new()
      {ctx, decompressed} = Compression.push(ctx, compressed)
      Compression.close(ctx)

      assert decompressed != nil, "Expected decompressed data but got nil (incomplete frame?)"

      hello = JSON.decode!(decompressed)
      assert hello["op"] == 10
      assert is_integer(hello["d"]["heartbeat_interval"])
    end
  end

  describe "identify flow" do
    test "sends identify and receives READY", %{gateway_url: url} do
      ws = connect(url, "v=10&encoding=json")

      {ws, [{:text, hello_json}]} = next_frames(ws)
      assert JSON.decode!(hello_json)["op"] == 10

      identify = Payload.identify(Lingo.Instance.get(:token), Intents.resolve([:guilds]), 0, 1)
      :ok = WebSocket.send_frame(ws, {:text, JSON.encode!(identify)})

      ready = receive_dispatch(ws, "READY", System.monotonic_time(:millisecond) + 15_000)

      assert ready != nil, "Did not receive READY event within timeout"
      assert ready["d"]["v"] != nil
      assert is_binary(ready["d"]["session_id"])
      assert is_binary(ready["d"]["resume_gateway_url"])
      assert is_map(ready["d"]["user"])
      assert ready["d"]["user"]["bot"] == true
      assert is_list(ready["d"]["guilds"])
      assert is_map(ready["d"]["application"])
    end
  end

  # loop until we see the dispatch event we want or give up
  defp receive_dispatch(ws, event_type, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0 do
      {ws, frames} = next_frames(ws, remaining)

      Enum.find_value(frames, fn
        {:text, json} -> match_dispatch(JSON.decode!(json), event_type)
        _other -> nil
      end) || receive_dispatch(ws, event_type, deadline)
    end
  end

  defp match_dispatch(%{"op" => 0, "t" => event_type} = message, event_type), do: message
  defp match_dispatch(_message, _event_type), do: nil
end
