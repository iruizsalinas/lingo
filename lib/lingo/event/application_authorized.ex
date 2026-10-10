defmodule Lingo.Event.ApplicationAuthorized do
  @moduledoc """
  The payload of the `:application_authorized` webhook event: a user added
  the application to a guild (`integration_type: :guild`, with `guild`) or
  to their account (`:user`).
  """

  alias Lingo.Type.{Guild, User}

  @type t :: %__MODULE__{
          integration_type: :guild | :user | integer() | nil,
          user: User.t(),
          scopes: [String.t()],
          guild: Guild.t() | nil
        }

  defstruct [:integration_type, :user, :guild, scopes: []]

  @integration_types %{0 => :guild, 1 => :user}

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      integration_type:
        Map.get(@integration_types, data["integration_type"], data["integration_type"]),
      user: User.new(data["user"]),
      scopes: data["scopes"] || [],
      guild: Guild.new(data["guild"])
    }
  end
end
