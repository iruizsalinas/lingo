defmodule Lingo.Api.MultipartTest do
  use ExUnit.Case, async: true

  alias Lingo.Api.Multipart

  defp encode(parts) do
    {content_type, body} = Multipart.encode(parts, "BOUNDARY")
    {content_type, IO.iodata_to_binary(body)}
  end

  test "encodes fields and files" do
    {content_type, body} =
      encode([
        {"payload_json", {~s({"content":"hi"}), content_type: "application/json"}},
        {"files[0]", {["hello", " world"], filename: "hello.txt"}},
        {"tags", "smile"},
        {"count", 3}
      ])

    assert content_type == "multipart/form-data; boundary=BOUNDARY"

    assert body ==
             """
             --BOUNDARY\r
             content-disposition: form-data; name="payload_json"\r
             content-type: application/json\r
             \r
             {"content":"hi"}\r
             --BOUNDARY\r
             content-disposition: form-data; name="files[0]"; filename="hello.txt"\r
             \r
             hello world\r
             --BOUNDARY\r
             content-disposition: form-data; name="tags"\r
             \r
             smile\r
             --BOUNDARY\r
             content-disposition: form-data; name="count"\r
             \r
             3\r
             --BOUNDARY--\r
             """
  end

  test "skips parts without a value" do
    {_content_type, body} = encode([{"name", "sticker"}, {"description", nil}])
    refute body =~ "description"
  end

  test "escapes quotes and line breaks in names and filenames" do
    {_content_type, body} = encode([{"file", {"data", filename: "a\"b\r\nc.png"}}])
    assert body =~ ~s(filename="a%22b%0D%0Ac.png")
  end

  test "generates a random boundary by default" do
    {"multipart/form-data; boundary=" <> boundary, body} = Multipart.encode([{"a", "b"}])

    assert byte_size(boundary) == 32
    assert IO.iodata_to_binary(body) =~ "--#{boundary}--\r\n"
  end
end
