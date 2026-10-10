defmodule Lingo.Rest.Multipart do
  @moduledoc false

  # Encodes multipart/form-data bodies (RFC 7578).
  #
  # Parts are `{name, value}` or `{name, {value, opts}}`, where value is
  # iodata or an integer and opts may hold `:filename` and `:content_type`.
  # Parts with a nil value are skipped.

  @type value :: iodata() | integer()
  @type part :: {String.t(), value() | {value(), keyword()} | nil}

  @spec encode([part()], String.t()) :: {content_type :: String.t(), iodata()}
  def encode(parts, boundary \\ random_boundary()) do
    body = [
      for({name, value} <- parts, value != nil, do: encode_part(name, value, boundary)),
      "--",
      boundary,
      "--\r\n"
    ]

    {"multipart/form-data; boundary=" <> boundary, body}
  end

  defp encode_part(name, {value, opts}, boundary) do
    disposition = ["form-data; name=\"", escape(name), "\"", filename(opts[:filename])]

    headers =
      [{"content-disposition", disposition}, {"content-type", opts[:content_type]}]
      |> Enum.reject(fn {_name, value} -> value == nil end)
      |> Enum.map(fn {name, value} -> [name, ": ", value, "\r\n"] end)

    ["--", boundary, "\r\n", headers, "\r\n", to_iodata(value), "\r\n"]
  end

  defp encode_part(name, value, boundary), do: encode_part(name, {value, []}, boundary)

  defp filename(nil), do: []
  defp filename(filename), do: ["; filename=\"", escape(filename), "\""]

  # quotes and line breaks would break out of the header, so percent-encode
  # them the way browsers do
  defp escape(string) do
    string
    |> String.replace("\"", "%22")
    |> String.replace("\r", "%0D")
    |> String.replace("\n", "%0A")
  end

  defp to_iodata(value) when is_integer(value), do: Integer.to_string(value)
  defp to_iodata(value), do: value

  defp random_boundary, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
end
