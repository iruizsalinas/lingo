defmodule Lingo.Context.ResponseTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Lingo.Context

  setup do
    test_pid = self()

    http = fn method, url, _headers, body ->
      body =
        case body do
          {_content_type, body} -> body |> IO.iodata_to_binary() |> JSON.decode!()
          nil -> nil
        end

      send(test_pid, {:request, method, URI.parse(url).path, body})

      Process.get(:response) ||
        {:ok,
         %{
           status: 200,
           headers: [{"content-type", "application/json"}],
           body: JSON.encode!(%{"id" => "m1"})
         }}
    end

    bot = Lingo.TestBot.start(http_request: http, application_id: "app", start: [:rate_limiter])

    ctx = %Context{
      bot: bot,
      interaction_id: "i1",
      interaction_token: "tok",
      application_id: "app"
    }

    {:ok, ctx: ctx}
  end

  test "the first reply answers the interaction, later ones follow up", %{ctx: ctx} do
    assert {:ok, ctx} = Lingo.Context.reply(ctx, "one")
    assert ctx.replied
    assert_receive {:request, :post, "/api/v10/interactions/i1/tok/callback", %{"type" => 4}}

    ctx = Lingo.Context.reply!(ctx, content: "two")
    assert_receive {:request, :post, "/api/v10/webhooks/app/tok", %{"content" => "two"}}
    assert ctx.replied
  end

  test "ephemeral keeps existing flags", %{ctx: ctx} do
    assert {:ok, _} = Lingo.Context.ephemeral(ctx, %{components: [], flags: 1 <<< 15})

    assert_receive {:request, :post, "/api/v10/interactions/i1/tok/callback", body}
    assert body["data"]["flags"] == (1 <<< 15 ||| 1 <<< 6)
  end

  test "replying after a defer does not send the EPHEMERAL flag on the edit", %{ctx: ctx} do
    ctx = %{ctx | deferred: true}
    assert {:ok, ctx} = Lingo.Context.ephemeral(ctx, "hi")
    refute ctx.deferred

    assert_receive {:request, :patch, "/api/v10/webhooks/app/tok/messages/@original", body}
    assert body == %{"content" => "hi"}
  end

  test "get_reply, update_reply and delete_reply act on the response message", %{ctx: ctx} do
    assert {:ok, %Lingo.Type.Message{id: "m1"}} = Lingo.Context.get_reply(ctx)
    assert_receive {:request, :get, "/api/v10/webhooks/app/tok/messages/@original", nil}

    assert %Context{replied: true} = Lingo.Context.update_reply!(ctx, %{content: "x", flags: 64})
    assert_receive {:request, :patch, "/api/v10/webhooks/app/tok/messages/@original", body}
    assert body == %{"content" => "x"}

    assert %Context{} = Lingo.Context.delete_reply!(ctx)
    assert_receive {:request, :delete, "/api/v10/webhooks/app/tok/messages/@original", nil}
  end

  test "launch_activity answers with LAUNCH_ACTIVITY", %{ctx: ctx} do
    assert %Context{replied: true} = Lingo.Context.launch_activity!(ctx)
    assert_receive {:request, :post, "/api/v10/interactions/i1/tok/callback", %{"type" => 12}}
  end

  test "defer, show_modal and autocomplete_result return the context", %{ctx: ctx} do
    assert %Context{deferred: true} = Lingo.Context.defer!(ctx, ephemeral: true)
    assert_receive {:request, :post, _path, %{"type" => 5, "data" => %{"flags" => 64}}}

    assert %Context{replied: true} =
             Lingo.Context.show_modal!(ctx, %{custom_id: "m", title: "T", components: []})

    assert_receive {:request, :post, _path, %{"type" => 9}}

    assert %Context{replied: true} =
             Lingo.Context.autocomplete_result!(ctx, [[name: "A", value: "a"]])

    assert_receive {:request, :post, _path,
                    %{"type" => 8, "data" => %{"choices" => [%{"name" => "A", "value" => "a"}]}}}
  end

  test "bang functions raise Lingo.Error", %{ctx: ctx} do
    Process.put(
      :response,
      {:ok,
       %{
         status: 400,
         headers: [{"content-type", "application/json"}],
         body:
           JSON.encode!(%{
             "code" => 40060,
             "message" => "Interaction has already been acknowledged."
           })
       }}
    )

    error = assert_raise Lingo.Error, fn -> Lingo.Context.reply!(ctx, "hi") end
    assert error.code == 40060
    assert Exception.message(error) =~ "already been acknowledged"
  end

  test "a context answers for its own bot, from any process", %{ctx: ctx} do
    # a second bot is running, and this process has neither selected
    _other = Lingo.TestBot.start()
    Process.delete({Lingo, :current_bot})

    task = Task.async(fn -> Lingo.Context.reply(ctx, "from elsewhere") end)
    assert {:ok, _ctx} = Task.await(task)
  end
end
