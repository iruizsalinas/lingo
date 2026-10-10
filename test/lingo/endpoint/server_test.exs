defmodule Lingo.Endpoint.ServerTest do
  use ExUnit.Case, async: true

  defmodule ServerBot do
    use Lingo.Bot

    command("ping", "Pong")

    @impl true
    def handle_command("ping", ctx), do: reply!(ctx, "Pong")
  end

  setup do
    {public, secret} = :crypto.generate_key(:eddsa, :ed25519)
    test_pid = self()
    name = Module.concat(__MODULE__, "Bot#{System.unique_integer([:positive])}")

    http = fn method, url, _headers, _body ->
      path = URI.parse(url).path
      send(test_pid, {:rest, method, path})
      body = if path == "/api/v10/applications/@me", do: ~s({"id":"200"}), else: "[]"
      {:ok, %{status: 200, headers: [{"content-type", "application/json"}], body: body}}
    end

    opts = [
      name: name,
      bot: ServerBot,
      token: "t",
      http_request: http,
      gateway: false,
      register_commands: :global,
      endpoint: [public_key: Base.encode16(public), port: 0, ip: {127, 0, 0, 1}]
    ]

    sup =
      start_supervised!(%{
        id: name,
        start: {Lingo.Supervisor, :start_link, [opts]},
        type: :supervisor
      })

    {_, server, _, _} =
      sup |> Supervisor.which_children() |> List.keyfind(Lingo.Endpoint.Server, 0)

    %{port: Lingo.Endpoint.Server.port(server), secret: secret, sup: sup}
  end

  defp post(port, path, body, headers) do
    headers = Enum.map(headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end)
    url = ~c"http://127.0.0.1:#{port}#{path}"

    {:ok, {{_, status, _}, resp_headers, resp_body}} =
      :httpc.request(:post, {url, headers, ~c"application/json", body}, [], body_format: :binary)

    {status, Map.new(resp_headers, fn {k, v} -> {to_string(k), to_string(v)} end), resp_body}
  end

  defp signed(body, secret) do
    ts = "1700000000"
    sig = :crypto.sign(:eddsa, :none, ts <> body, [secret, :ed25519])
    [{"x-signature-ed25519", Base.encode16(sig)}, {"x-signature-timestamp", ts}]
  end

  test "registers commands at start when there's no gateway", %{sup: sup} do
    assert_receive {:rest, :put, "/api/v10/applications/200/commands"}, 2_000

    refute Enum.any?(
             Supervisor.which_children(sup),
             &match?({Lingo.Gateway.ShardManager, _, _, _}, &1)
           )
  end

  test "answers PINGs on both paths", %{port: port, secret: secret} do
    ping = ~s({"type":1,"id":"1","application_id":"200","token":"t","version":1})

    assert {200, %{"content-type" => "application/json"}, ~s({"type":1})} =
             post(port, "/interactions", ping, signed(ping, secret))

    event_ping = ~s({"version":1,"application_id":"200","type":0})

    assert {204, %{"content-type" => "application/json"}, ""} =
             post(port, "/events", event_ping, signed(event_ping, secret))
  end

  test "refuses bad signatures, other paths and other methods", %{port: port, secret: secret} do
    ping = ~s({"type":1})
    assert {401, _, _} = post(port, "/interactions", ping, signed(ping <> " ", secret))
    assert {404, _, _} = post(port, "/elsewhere", ping, signed(ping, secret))

    {:ok, {{_, status, _}, _, _}} =
      :httpc.request(:get, {~c"http://127.0.0.1:#{port}/interactions", []}, [], [])

    assert status == 405
  end

  test "an interaction is answered through its callback, then the request with 202", %{
    port: port,
    secret: secret
  } do
    body =
      JSON.encode!(%{
        id: "900",
        application_id: "200",
        type: 2,
        token: "tok",
        version: 1,
        channel_id: "10",
        user: %{id: "30", username: "u"},
        data: %{id: "40", name: "ping", type: 1}
      })

    assert {202, _, ""} = post(port, "/interactions", body, signed(body, secret))
    assert_received {:rest, :post, "/api/v10/interactions/900/tok/callback"}
  end
end
