defmodule Lingo.ErrorTest do
  use ExUnit.Case, async: true

  alias Lingo.Error

  test "Discord's error responses keep their code, message and field errors" do
    body = %{
      "code" => 50035,
      "message" => "Invalid Form Body",
      "errors" => %{"content" => %{"_errors" => [%{"code" => "BASE_TYPE_MAX_LENGTH"}]}}
    }

    error = Error.from_response(400, body)

    assert %Error{reason: :api, status: 400, code: 50035, message: "Invalid Form Body"} = error
    assert error.errors["content"]
    assert Exception.message(error) =~ "Discord returned 400 (code 50035): Invalid Form Body"
    assert Exception.message(error) =~ "BASE_TYPE_MAX_LENGTH"
  end

  test "non-JSON error bodies are kept as details" do
    error = Error.from_response(502, "<html>Bad Gateway</html>")

    assert %Error{reason: :api, status: 502, code: nil, details: "<html>Bad Gateway</html>"} =
             error

    assert Exception.message(error) =~ "Bad Gateway"
  end

  test "messages for the other reasons" do
    assert Exception.message(%Error{reason: :rate_limited, retry_after: 1500}) =~ "1500ms"
    assert Exception.message(%Error{reason: :server_error, status: 503}) =~ "503"
    assert Exception.message(%Error{reason: :transport, details: :econnrefused}) =~ "econnrefused"
    assert Exception.message(%Error{reason: :index_not_ready}) =~ "indexed"
  end

  test "can be raised" do
    assert_raise Error, ~r/Unknown Message/, fn ->
      raise Error.from_response(404, %{"code" => 10008, "message" => "Unknown Message"})
    end
  end
end
