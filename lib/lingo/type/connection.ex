defmodule Lingo.Type.Connection do
  @moduledoc """
  An account a user connected to Discord (`connections` OAuth2 scope):
  `type` is the service, such as `"github"` or `"steam"`, and `name` the
  account's name there. `integrations` are partial guild integrations.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          type: String.t(),
          revoked: boolean(),
          verified: boolean(),
          friend_sync: boolean(),
          show_activity: boolean(),
          two_way_link: boolean(),
          visibility: :none | :everyone | integer(),
          integrations: [Lingo.Type.Integration.t()]
        }

  defstruct [
    :id,
    :name,
    :type,
    revoked: false,
    verified: false,
    friend_sync: false,
    show_activity: false,
    two_way_link: false,
    visibility: :none,
    integrations: []
  ]

  @visibility %{0 => :none, 1 => :everyone}

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    connection = Lingo.Type.Parse.fields(__MODULE__, data)

    %{
      connection
      | visibility: Map.get(@visibility, data["visibility"], connection.visibility),
        integrations: Lingo.Type.Parse.list(data["integrations"], &Lingo.Type.Integration.new/1)
    }
  end
end
