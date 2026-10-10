defmodule Lingo.Testing.Stub do
  @moduledoc false

  # Stands in for Discord's API in Lingo.Testing: every call is reported to
  # the test process, and answered by the test's :rest function or a default.

  def new(test_pid, rest) do
    fn method, url, _headers, body ->
      uri = URI.parse(url)
      path = String.replace_prefix(uri.path, "/api/v10", "")
      body = decode(body)
      send(test_pid, {Lingo.Testing, %{method: method, path: path, query: uri.query, body: body}})

      {status, response} =
        cond do
          rest -> rest.(method, path, body)
          String.ends_with?(path, "/callback") -> {204, nil}
          true -> {200, %{}}
        end

      headers = if response, do: [{"content-type", "application/json"}], else: []
      {:ok, %{status: status, headers: headers, body: encode(response)}}
    end
  end

  defp decode({"application/json", iodata}), do: iodata |> IO.iodata_to_binary() |> JSON.decode!()
  defp decode(other), do: other

  defp encode(nil), do: ""
  defp encode(response), do: JSON.encode!(response)
end
