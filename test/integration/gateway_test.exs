defmodule Lingo.Integration.GatewayTest do
  @moduledoc false
  use Lingo.IntegrationCase

  describe "gateway handshake" do
    test "connects to gateway and receives Hello (op 10)" do
      token = Lingo.Config.token()

      headers = [
        {"authorization", "Bot #{token}"},
        {"user-agent", "DiscordBot (lingo-test, 0.1.0)"}
      ]

      {:ok, %{body: body}} = Req.get("https://discord.com/api/v10/gateway/bot", headers: headers)
      gateway_host = body["url"] |> String.replace("wss://", "")

      {:ok, pid} =
        :gun.open(String.to_charlist(gateway_host), 443, %{
          protocols: [:http],
          transport: :tls,
          tls_opts: [
            verify: :verify_peer,
            cacerts: :public_key.cacerts_get(),
            customize_hostname_check: [
              match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
            ]
          ]
        })

      assert_receive {:gun_up, ^pid, :http}, 10_000

      ref = :gun.ws_upgrade(pid, ~c"/?v=10&encoding=json", [], %{silence_pings: false})

      assert_receive {:gun_upgrade, ^pid, ^ref, ["websocket"], _headers}, 10_000

      # first thing we get should be hello
      assert_receive {:gun_ws, ^pid, ^ref, {:text, hello_json}}, 10_000

      hello = Jason.decode!(hello_json)
      assert hello["op"] == 10
      assert is_integer(hello["d"]["heartbeat_interval"])
      assert hello["d"]["heartbeat_interval"] > 0

      :gun.close(pid)
    end
  end

  describe "zlib-stream gateway connection" do
    test "connects with zlib compression and receives decompressable Hello" do
      token = Lingo.Config.token()

      headers = [
        {"authorization", "Bot #{token}"},
        {"user-agent", "DiscordBot (lingo-test, 0.1.0)"}
      ]

      {:ok, %{body: body}} = Req.get("https://discord.com/api/v10/gateway/bot", headers: headers)
      gateway_host = body["url"] |> String.replace("wss://", "")

      {:ok, pid} =
        :gun.open(String.to_charlist(gateway_host), 443, %{
          protocols: [:http],
          transport: :tls,
          tls_opts: [
            verify: :verify_peer,
            cacerts: :public_key.cacerts_get(),
            customize_hostname_check: [
              match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
            ]
          ]
        })

      assert_receive {:gun_up, ^pid, :http}, 10_000

      ref =
        :gun.ws_upgrade(pid, ~c"/?v=10&encoding=json&compress=zlib-stream", [], %{
          silence_pings: false
        })

      assert_receive {:gun_upgrade, ^pid, ^ref, ["websocket"], _headers}, 10_000

      # binary frame since we asked for zlib
      assert_receive {:gun_ws, ^pid, ^ref, {:binary, compressed_data}}, 10_000

      ctx = Lingo.Gateway.Compression.new()
      {ctx, decompressed} = Lingo.Gateway.Compression.push(ctx, compressed_data)

      assert decompressed != nil, "Expected decompressed data but got nil (incomplete frame?)"

      hello = Jason.decode!(decompressed)
      assert hello["op"] == 10
      assert is_integer(hello["d"]["heartbeat_interval"])

      Lingo.Gateway.Compression.close(ctx)
      :gun.close(pid)
    end
  end

  describe "identify flow" do
    test "sends identify and receives READY" do
      token = Lingo.Config.token()

      headers = [
        {"authorization", "Bot #{token}"},
        {"user-agent", "DiscordBot (lingo-test, 0.1.0)"}
      ]

      {:ok, %{body: body}} = Req.get("https://discord.com/api/v10/gateway/bot", headers: headers)
      gateway_host = body["url"] |> String.replace("wss://", "")

      {:ok, pid} =
        :gun.open(String.to_charlist(gateway_host), 443, %{
          protocols: [:http],
          transport: :tls,
          tls_opts: [
            verify: :verify_peer,
            cacerts: :public_key.cacerts_get(),
            customize_hostname_check: [
              match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
            ]
          ]
        })

      assert_receive {:gun_up, ^pid, :http}, 10_000

      ref = :gun.ws_upgrade(pid, ~c"/?v=10&encoding=json", [], %{silence_pings: false})
      assert_receive {:gun_upgrade, ^pid, ^ref, ["websocket"], _headers}, 10_000

      assert_receive {:gun_ws, ^pid, ^ref, {:text, hello_json}}, 10_000
      hello = Jason.decode!(hello_json)
      assert hello["op"] == 10

      identify =
        Lingo.Gateway.Payload.identify(
          token,
          Lingo.Gateway.Intents.resolve([:guilds]),
          0,
          1
        )

      :gun.ws_send(pid, ref, {:text, Jason.encode!(identify)})

      # might get heartbeat requests first, so loop until READY
      ready = receive_dispatch(pid, ref, "READY", 15_000)

      assert ready != nil, "Did not receive READY event within timeout"
      assert ready["t"] == "READY"
      assert ready["d"]["v"] != nil
      assert is_binary(ready["d"]["session_id"])
      assert is_binary(ready["d"]["resume_gateway_url"])
      assert is_map(ready["d"]["user"])
      assert ready["d"]["user"]["bot"] == true
      assert is_list(ready["d"]["guilds"])
      assert is_map(ready["d"]["application"])

      :gun.close(pid)
    end
  end

  # loop until we see the dispatch event we want or give up
  defp receive_dispatch(pid, ref, event_type, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout

    receive_dispatch_loop(pid, ref, event_type, deadline)
  end

  defp receive_dispatch_loop(pid, ref, event_type, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      nil
    else
      receive do
        {:gun_ws, ^pid, ^ref, {:text, json}} ->
          msg = Jason.decode!(json)

          if msg["op"] == 0 and msg["t"] == event_type do
            msg
          else
            receive_dispatch_loop(pid, ref, event_type, deadline)
          end

        {:gun_ws, ^pid, ^ref, _other} ->
          receive_dispatch_loop(pid, ref, event_type, deadline)
      after
        min(remaining, 5_000) ->
          nil
      end
    end
  end
end
