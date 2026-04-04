defmodule Lingo.Type.Emoji do
  @moduledoc false

  alias Lingo.Type.User

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          roles: [String.t()],
          user: User.t() | nil,
          require_colons: boolean(),
          managed: boolean(),
          animated: boolean(),
          available: boolean()
        }

  defstruct [
    :id,
    :name,
    :user,
    roles: [],
    require_colons: false,
    managed: false,
    animated: false,
    available: true
  ]

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      name: data["name"],
      roles: data["roles"] || [],
      user: User.new(data["user"]),
      require_colons: data["require_colons"] || false,
      managed: data["managed"] || false,
      animated: data["animated"] || false,
      available: data["available"] != false
    }
  end

  @spec format(t()) :: String.t()
  def format(%__MODULE__{id: nil, name: name}), do: name
  def format(%__MODULE__{animated: true, name: name, id: id}), do: "<a:#{name}:#{id}>"
  def format(%__MODULE__{name: name, id: id}), do: "<:#{name}:#{id}>"
end
