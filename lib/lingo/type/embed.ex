defmodule Lingo.Type.Embed do
  @moduledoc "A message embed. Build one with `Lingo.Embed.build/1`."

  @type t :: %__MODULE__{
          title: String.t() | nil,
          type: String.t() | nil,
          description: String.t() | nil,
          url: String.t() | nil,
          timestamp: DateTime.t() | nil,
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

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      title: data["title"],
      type: data["type"],
      description: data["description"],
      url: data["url"],
      timestamp: Lingo.Type.Parse.timestamp(data["timestamp"]),
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

  @doc false
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = embed) do
    embed
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
