defmodule Lingo.Rest.Body do
  @moduledoc false

  # Request bodies: JSON, or multipart/form-data when the params carry
  # `:files` as `{filename, binary}` tuples.

  @spec opts(String.t() | keyword() | map()) :: keyword()
  def opts(content) when is_binary(content), do: [json: %{content: content}]
  def opts(params) when is_list(params), do: opts(Map.new(params))

  def opts(params) when is_map(params) do
    case Map.pop(params, :files) do
      {nil, json} -> [json: json]
      {files, json} -> [multipart: multipart(json, files)]
    end
  end

  @spec multipart(map(), [{String.t(), iodata()}]) :: [Lingo.Rest.Multipart.part()]
  def multipart(json, files) do
    payload = {"payload_json", {JSON.encode!(json), content_type: "application/json"}}

    parts =
      files
      |> Enum.with_index()
      |> Enum.map(fn {{filename, data}, index} ->
        {"files[#{index}]", {data, filename: filename}}
      end)

    [payload | parts]
  end
end
