defmodule Lingo.Event.GuildRoleDelete do
  @moduledoc "The payload of `:guild_role_delete`. `old` is the role as cached, or `nil`."

  alias Lingo.Type.Role

  @type t :: %__MODULE__{guild_id: String.t(), role_id: String.t(), old: Role.t() | nil}

  defstruct [:guild_id, :role_id, :old]

  @doc false
  def new(nil), do: nil
  def new(data) when is_map(data), do: Lingo.Type.Parse.fields(__MODULE__, data)
end
