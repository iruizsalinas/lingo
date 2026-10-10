defmodule Lingo.Event.InviteDelete do
  @moduledoc "The payload of `:invite_delete`."

  @type t :: %__MODULE__{channel_id: String.t(), guild_id: String.t() | nil, code: String.t()}

  defstruct [:channel_id, :guild_id, :code]

  @doc false
  def new(nil), do: nil
  def new(data) when is_map(data), do: Lingo.Type.Parse.fields(__MODULE__, data)
end
