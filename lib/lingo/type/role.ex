defmodule Lingo.Type.Role do
  @moduledoc false

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          color: integer(),
          hoist: boolean(),
          icon: String.t() | nil,
          unicode_emoji: String.t() | nil,
          position: integer(),
          permissions: String.t(),
          managed: boolean(),
          mentionable: boolean(),
          tags: map() | nil,
          flags: integer()
        }

  defstruct [
    :id,
    :name,
    :icon,
    :unicode_emoji,
    :permissions,
    :tags,
    color: 0,
    hoist: false,
    position: 0,
    managed: false,
    mentionable: false,
    flags: 0
  ]

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      name: data["name"],
      color: data["color"] || 0,
      hoist: data["hoist"] || false,
      icon: data["icon"],
      unicode_emoji: data["unicode_emoji"],
      position: data["position"] || 0,
      permissions: data["permissions"],
      managed: data["managed"] || false,
      mentionable: data["mentionable"] || false,
      tags: data["tags"],
      flags: data["flags"] || 0
    }
  end
end
