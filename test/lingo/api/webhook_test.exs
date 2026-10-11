defmodule Lingo.Api.WebhookTest do
  use ExUnit.Case, async: true

  import Lingo.FakeRest, only: [respond: 1, respond: 2]

  alias Lingo.Api.Webhook

  setup do
    Lingo.FakeRest.start()
    :ok
  end

  for kind <- [:slack, :github] do
    test "#{kind}-compatible webhooks answer :ok, with or without a body" do
      fun = :"execute_#{unquote(kind)}"
      path = "/api/v10/webhooks/w1/token/#{unquote(kind)}"

      respond("ok")
      assert :ok = apply(Webhook, fun, ["w1", "token", %{text: "hi"}, [thread_id: "t1"]])
      assert_received {:request, :post, ^path, [{"thread_id", "t1"}], %{"text" => "hi"}}

      respond(204, nil)
      assert :ok = apply(Webhook, fun, ["w1", "token", %{text: "hi"}])

      respond(404, %{"code" => 10_015, "message" => "Unknown Webhook"})
      assert {:error, %Lingo.Error{status: 404}} = apply(Webhook, fun, ["w1", "token", %{}])
    end
  end
end
