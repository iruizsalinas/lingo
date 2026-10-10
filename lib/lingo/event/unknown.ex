defmodule Lingo.Event.Unknown do
  @moduledoc """
  The payload of `:unknown`: an event Lingo doesn't know yet. `type` is
  Discord's name for it, such as `"GUILD_SOMETHING_NEW"`, and `data` its
  payload as Discord sent it, with string keys.
  """

  @type t :: %__MODULE__{type: String.t(), data: term()}

  defstruct [:type, :data]

  @doc false
  @spec new(String.t(), term()) :: t()
  def new(type, data), do: %__MODULE__{type: type, data: data}
end
