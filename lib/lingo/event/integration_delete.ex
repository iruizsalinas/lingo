defmodule Lingo.Event.IntegrationDelete do
  @moduledoc """
  The payload of `:integration_delete`. `application_id` is set when the
  integration was a bot or OAuth2 application.
  """

  @type t :: %__MODULE__{id: String.t(), guild_id: String.t(), application_id: String.t() | nil}

  defstruct [:id, :guild_id, :application_id]

  @doc false
  def new(nil), do: nil
  def new(data) when is_map(data), do: Lingo.Type.Parse.fields(__MODULE__, data)
end
