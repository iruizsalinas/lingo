defmodule Lingo.Type.Sticker do
  @moduledoc false

  alias Lingo.Type.User

  @type format_type :: :png | :apng | :lottie | :gif
  @type sticker_type :: :standard | :guild

  @type t :: %__MODULE__{
          id: String.t(),
          pack_id: String.t() | nil,
          name: String.t(),
          description: String.t() | nil,
          tags: String.t(),
          type: sticker_type() | nil,
          format_type: format_type(),
          available: boolean(),
          guild_id: String.t() | nil,
          user: User.t() | nil,
          sort_value: integer() | nil
        }

  defstruct [
    :id,
    :pack_id,
    :name,
    :description,
    :tags,
    :type,
    :format_type,
    :guild_id,
    :user,
    :sort_value,
    available: true
  ]

  @format_types %{1 => :png, 2 => :apng, 3 => :lottie, 4 => :gif}
  @sticker_types %{1 => :standard, 2 => :guild}

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      pack_id: data["pack_id"],
      name: data["name"],
      description: data["description"],
      tags: data["tags"] || "",
      type: Map.get(@sticker_types, data["type"]),
      format_type: Map.get(@format_types, data["format_type"], :png),
      available: data["available"] != false,
      guild_id: data["guild_id"],
      user: User.new(data["user"]),
      sort_value: data["sort_value"]
    }
  end
end
