defmodule Lingo.Event.LobbyMessageDelete do
  @moduledoc "The payload of the `:lobby_message_delete` webhook event."

  @type t :: %__MODULE__{id: String.t(), lobby_id: String.t()}

  defstruct [:id, :lobby_id]

  @doc false
  def new(nil), do: nil
  def new(data) when is_map(data), do: Lingo.Type.Parse.fields(__MODULE__, data)
end
