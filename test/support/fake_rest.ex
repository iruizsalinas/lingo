defmodule Lingo.FakeRest do
  @moduledoc false

  # Stands in for Discord's REST API in a test bot: `start/1` starts a bot
  # whose requests go to the test, and `respond/2` sets Discord's answer.
  # Each request reaches the test as {:request, method, path, query, body},
  # the query as a list of pairs and the JSON body decoded.

  @doc "Starts a test bot (options as `Lingo.TestBot.start/1`) answering 204."
  def start(opts \\ []) do
    bot = Lingo.TestBot.start(Keyword.put_new(opts, :start, [:rate_limiter]))
    respond(204, nil)
    bot
  end

  @doc "Answers the bot's next requests with `status` and `body` (encoded to JSON)."
  def respond(status \\ 200, body) do
    test_pid = self()

    Lingo.Instance.put(Lingo.Instance.current(), :http_request, fn method, url, _headers, req ->
      uri = URI.parse(url)
      query = Enum.to_list(URI.query_decoder(uri.query || ""))
      send(test_pid, {:request, method, uri.path, query, json(req)})

      {:ok,
       %{
         status: status,
         headers: [{"content-type", "application/json"}],
         body: if(body == nil, do: "", else: JSON.encode!(body))
       }}
    end)
  end

  defp json(nil), do: nil
  defp json({"application/json", body}), do: body |> IO.iodata_to_binary() |> JSON.decode!()
  defp json({_content_type, body}), do: IO.iodata_to_binary(body)
end
