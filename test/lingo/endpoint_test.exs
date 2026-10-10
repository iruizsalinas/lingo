defmodule Lingo.EndpointTest do
  use ExUnit.Case, async: true

  alias Lingo.Endpoint
  alias Lingo.Type.{Entitlement, User}

  defmodule HttpBot do
    use Lingo.Bot

    command("ping", "Pong")
    command("silent", "Never answers")

    @impl true
    def handle_command("ping", ctx), do: reply!(ctx, "Pong")
    def handle_command("silent", _ctx), do: :ok

    @impl true
    def handle_event(event, data), do: send(Lingo.Instance.get(:test_pid), {:event, event, data})
  end

  setup do
    {public, secret} = :crypto.generate_key(:eddsa, :ed25519)
    test_pid = self()

    # Discord's REST API: records interaction callbacks
    http = fn method, url, _headers, body ->
      send(test_pid, {:rest, method, URI.parse(url).path, body})
      {:ok, %{status: 204, headers: [], body: ""}}
    end

    bot =
      Lingo.TestBot.start(
        bot: HttpBot,
        test_pid: self(),
        http_request: http,
        start: [:rate_limiter, :collector, :pending]
      )

    Lingo.Instance.put(bot, :endpoint, public_key: Base.encode16(public, case: :lower))
    %{secret: secret, public: public, bot: bot}
  end

  defp signed(body, secret, timestamp \\ "1700000000") do
    signature = :crypto.sign(:eddsa, :none, timestamp <> body, [secret, :ed25519])

    [
      {"X-Signature-Ed25519", Base.encode16(signature, case: :lower)},
      {"X-Signature-Timestamp", timestamp}
    ]
  end

  defp interaction(name) do
    JSON.encode!(%{
      id: "900",
      application_id: "200",
      type: 2,
      token: "tok",
      version: 1,
      channel_id: "10",
      guild_id: "20",
      member: %{user: %{id: "30", username: "u"}, roles: []},
      data: %{id: "40", name: name, type: 1}
    })
  end

  describe "signatures" do
    # RFC 8032, section 7.1, tests 1 and 2: the signed message is the
    # timestamp followed by the body, here "" and "r" (0x72)
    test "match the RFC 8032 Ed25519 vectors" do
      key1 = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"

      sig1 =
        "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155" <>
          "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"

      key2 = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"

      sig2 =
        "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da" <>
          "085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"

      headers = fn sig, ts -> [{"x-signature-ed25519", sig}, {"x-signature-timestamp", ts}] end

      assert Endpoint.valid_signature?(headers.(sig1, ""), "", key1)
      assert Endpoint.valid_signature?(headers.(sig2, "r"), "", key2)
      assert Endpoint.valid_signature?(headers.(sig2, ""), "r", key2)
      refute Endpoint.valid_signature?(headers.(sig2, "r"), "s", key2)
      refute Endpoint.valid_signature?(headers.(sig1, ""), "", key2)
    end

    test "missing or malformed headers are invalid", %{public: public} do
      key = Base.encode16(public)
      refute Endpoint.valid_signature?([], "{}", key)
      refute Endpoint.valid_signature?([{"x-signature-timestamp", "1"}], "{}", key)

      refute Endpoint.valid_signature?(
               [{"x-signature-ed25519", "zz"}, {"x-signature-timestamp", "1"}],
               "{}",
               key
             )
    end
  end

  describe "interactions" do
    test "answers PING with PONG", %{secret: secret} do
      body = ~s({"type":1,"id":"1","application_id":"200","token":"t","version":1})

      assert {200, [{"content-type", "application/json"}], ~s({"type":1})} =
               Endpoint.interaction(signed(body, secret), body)

      refute_received {:rest, _, _, _}
    end

    test "rejects bad signatures with 401", %{secret: secret} do
      body = interaction("ping")
      headers = signed(body, secret)

      assert {401, _, _} = Endpoint.interaction(headers, body <> " ")
      # signed for another timestamp
      [signature, _timestamp] = headers
      assert {401, _, _} = Endpoint.interaction([signature, {"x-signature-timestamp", "1"}], body)
      assert {401, _, _} = Endpoint.interaction([], body)
      refute_received {:event, _, _}
    end

    test "rejects signed bodies that aren't interactions", %{secret: secret} do
      assert {400, _, _} = Endpoint.interaction(signed("nope", secret), "nope")
      assert {400, _, _} = Endpoint.interaction(signed("{}", secret), "{}")
    end

    test "hands the interaction to the bot and returns 202 once it's answered", %{secret: secret} do
      body = interaction("ping")
      {time, response} = :timer.tc(fn -> Endpoint.interaction(signed(body, secret), body) end)

      assert {202, _, ""} = response
      # the callback went out before the HTTP request was answered
      assert_received {:rest, :post, "/api/v10/interactions/900/tok/callback", _body}
      assert time < 2_000_000
    end

    @tag timeout: 10_000
    test "returns 202 after a while when the bot never answers", %{secret: secret} do
      body = interaction("silent")
      {time, response} = :timer.tc(fn -> Endpoint.interaction(signed(body, secret), body) end)

      assert {202, _, ""} = response
      assert time >= 2_400_000 and time < 3_000_000
      refute_received {:rest, _, _, _}
    end
  end

  describe "webhook events" do
    test "answers PING with an empty 204", %{secret: secret} do
      body = ~s({"version":1,"application_id":"200","type":0})

      assert {204, [{"content-type", "application/json"}], ""} =
               Endpoint.event(signed(body, secret), body)

      refute_received {:event, _, _}
    end

    test "rejects bad signatures with 401", %{secret: secret} do
      body = ~s({"version":1,"application_id":"200","type":0})
      assert {401, _, _} = Endpoint.event(signed(body, secret), body <> "x")
    end

    test "delivers an app authorization to handle_event", %{secret: secret} do
      body =
        JSON.encode!(%{
          version: 1,
          application_id: "200",
          type: 1,
          event: %{
            type: "APPLICATION_AUTHORIZED",
            timestamp: "2026-10-10T00:00:00.000000+00:00",
            data: %{
              integration_type: 0,
              scopes: ["applications.commands", "bot"],
              user: %{id: "30", username: "u"},
              guild: %{id: "20", name: "G"}
            }
          }
        })

      assert {204, _, ""} = Endpoint.event(signed(body, secret), body)

      assert_receive {:event, :application_authorized,
                      %{
                        integration_type: :guild,
                        scopes: ["applications.commands", "bot"],
                        user: %User{id: "30"},
                        guild: %{id: "20"}
                      }}
    end

    test "delivers entitlements as structs, and unknown events raw", %{secret: secret} do
      entitlement = %{id: "1", sku_id: "2", application_id: "200", user_id: "30", type: 8}

      wrap = fn type, data ->
        JSON.encode!(%{version: 1, type: 1, event: %{type: type, data: data}})
      end

      body = wrap.("ENTITLEMENT_CREATE", entitlement)
      assert {204, _, ""} = Endpoint.event(signed(body, secret), body)
      assert_receive {:event, :entitlement_create, %Entitlement{id: "1", sku_id: "2"}}

      body = wrap.("SOMETHING_NEW", %{"a" => 1})
      assert {204, _, ""} = Endpoint.event(signed(body, secret), body)
      assert_receive {:event, {:unknown_event, "SOMETHING_NEW"}, %{"a" => 1}}
    end
  end
end
