defmodule Lingo.Rest.HTTPTest do
  use ExUnit.Case, async: true

  alias Lingo.Rest.HTTP

  # serves one canned response and sends the raw request back to the test
  defp serve(response) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    test_pid = self()

    spawn_link(fn ->
      {:ok, socket} = :gen_tcp.accept(listen, 5_000)
      send(test_pid, {:request, read_request(socket, <<>>)})
      :gen_tcp.send(socket, response)
      :gen_tcp.close(socket)
    end)

    "http://127.0.0.1:#{port}"
  end

  defp read_request(socket, buffer) do
    with [head, body] <- String.split(buffer, "\r\n\r\n", parts: 2),
         true <- byte_size(body) >= content_length(head) do
      buffer
    else
      _incomplete ->
        {:ok, data} = :gen_tcp.recv(socket, 0, 5_000)
        read_request(socket, buffer <> data)
    end
  end

  defp content_length(head) do
    case Regex.run(~r/content-length: (\d+)/i, head) do
      [_, length] -> String.to_integer(length)
      nil -> 0
    end
  end

  test "sends a GET with headers and returns the response" do
    url =
      serve(
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\ncontent-length: 11\r\n\r\n{\"a\":true}\n"
      )

    assert {:ok, %{status: 200, headers: headers, body: "{\"a\":true}\n"}} =
             HTTP.request(:get, url <> "/users/@me?with_counts=true", [{"authorization", "Bot t"}])

    assert {"content-type", "application/json"} in headers

    assert_received {:request, request}
    assert request =~ "GET /users/@me?with_counts=true HTTP/1.1\r\n"
    assert request =~ "authorization: Bot t\r\n"
  end

  test "sends a body with its content type" do
    url = serve("HTTP/1.1 204 No Content\r\n\r\n")

    assert {:ok, %{status: 204, body: ""}} =
             HTTP.request(:patch, url <> "/channels/1", [], {"application/json", ["{", "}"]})

    assert_received {:request, request}
    assert request =~ "PATCH /channels/1 HTTP/1.1\r\n"
    assert request =~ "content-type: application/json\r\n"
    assert String.ends_with?(request, "\r\n\r\n{}")
  end

  test "sends an empty body for a POST without one" do
    url = serve("HTTP/1.1 204 No Content\r\n\r\n")

    assert {:ok, %{status: 204}} = HTTP.request(:post, url <> "/channels/1/typing", [])

    assert_received {:request, request}
    assert request =~ "content-length: 0\r\n"
    refute request =~ "content-type"
  end

  test "returns error statuses as responses" do
    url = serve("HTTP/1.1 429 Too Many Requests\r\nretry-after: 2\r\ncontent-length: 0\r\n\r\n")

    assert {:ok, %{status: 429, headers: headers}} = HTTP.request(:delete, url <> "/x", [])
    assert {"retry-after", "2"} in headers
  end

  test "does not follow redirects" do
    url =
      serve("HTTP/1.1 302 Found\r\nlocation: http://127.0.0.1:1/\r\ncontent-length: 0\r\n\r\n")

    assert {:ok, %{status: 302}} = HTTP.request(:get, url, [])
  end

  test "returns connection errors" do
    {:ok, listen} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(listen)
    :gen_tcp.close(listen)

    assert {:error, _reason} = HTTP.request(:get, "http://127.0.0.1:#{port}/", [])
  end
end
