defmodule Lingo.Type.Embed do
  @moduledoc false

  @type t :: %__MODULE__{
          title: String.t() | nil,
          type: String.t() | nil,
          description: String.t() | nil,
          url: String.t() | nil,
          timestamp: String.t() | nil,
          color: integer() | nil,
          footer: map() | nil,
          image: map() | nil,
          thumbnail: map() | nil,
          video: map() | nil,
          provider: map() | nil,
          author: map() | nil,
          fields: [map()]
        }

  defstruct [
    :title,
    :type,
    :description,
    :url,
    :timestamp,
    :color,
    :footer,
    :image,
    :thumbnail,
    :video,
    :provider,
    :author,
    fields: []
  ]

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      title: data["title"],
      type: data["type"],
      description: data["description"],
      url: data["url"],
      timestamp: data["timestamp"],
      color: data["color"],
      footer: data["footer"],
      image: data["image"],
      thumbnail: data["thumbnail"],
      video: data["video"],
      provider: data["provider"],
      author: data["author"],
      fields: data["fields"] || []
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = embed) do
    embed
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  def build(opts) when is_list(opts) do
    %{}
    |> put_if(:title, opts[:title])
    |> put_if(:description, opts[:description])
    |> put_if(:url, opts[:url])
    |> put_if(:color, opts[:color])
    |> put_if(:timestamp, opts[:timestamp])
    |> put_if(:image, wrap_url(opts[:image]))
    |> put_if(:thumbnail, wrap_url(opts[:thumbnail]))
    |> put_if(:footer, wrap_footer(opts[:footer]))
    |> put_if(:author, wrap_author(opts[:author]))
    |> put_if(:fields, non_empty(opts[:fields]))
  end

  defp wrap_url(nil), do: nil
  defp wrap_url(url) when is_binary(url), do: %{url: url}
  defp wrap_url(map) when is_map(map), do: map

  defp wrap_footer(nil), do: nil
  defp wrap_footer(text) when is_binary(text), do: %{text: text}
  defp wrap_footer(map) when is_map(map), do: map

  defp wrap_author(nil), do: nil
  defp wrap_author(name) when is_binary(name), do: %{name: name}
  defp wrap_author(map) when is_map(map), do: map

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp non_empty(nil), do: nil
  defp non_empty([]), do: nil
  defp non_empty(list) when is_list(list), do: list
end
