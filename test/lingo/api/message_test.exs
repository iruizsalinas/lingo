defmodule Lingo.Api.MessageTest do
  use ExUnit.Case, async: true

  alias Lingo.Api.Message

  setup do
    test_pid = self()

    http = fn method, url, _headers, {_content_type, body} ->
      body = body |> IO.iodata_to_binary() |> JSON.decode!()
      send(test_pid, {:request, method, URI.parse(url).path, body})

      {:ok,
       %{
         status: 200,
         headers: [{"content-type", "application/json"}],
         body: JSON.encode!(%{"id" => "m2", "channel_id" => "c2"})
       }}
    end

    Lingo.TestBot.start(http_request: http, start: [:rate_limiter])
    :ok
  end

  test "forward/3 sends a forwarding message reference" do
    assert {:ok, %Lingo.Type.Message{id: "m2"}} = Message.forward("c2", "c1", "m1")

    assert_receive {:request, :post, "/api/v10/channels/c2/messages",
                    %{
                      "message_reference" => %{
                        "type" => 1,
                        "channel_id" => "c1",
                        "message_id" => "m1"
                      }
                    }}
  end
end
