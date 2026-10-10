defmodule Lingo.Event.ApplicationDeauthorized do
  @moduledoc """
  The payload of the `:application_deauthorized` webhook event: a user
  removed the application from their account.
  """

  alias Lingo.Type.User

  @type t :: %__MODULE__{user: User.t()}

  defstruct [:user]

  @doc false
  def new(nil), do: nil
  def new(data) when is_map(data), do: %__MODULE__{user: User.new(data["user"])}
end
