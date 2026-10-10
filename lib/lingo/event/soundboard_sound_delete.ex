defmodule Lingo.Event.SoundboardSoundDelete do
  @moduledoc "The payload of `:guild_soundboard_sound_delete`."

  @type t :: %__MODULE__{sound_id: String.t(), guild_id: String.t()}

  defstruct [:sound_id, :guild_id]

  @doc false
  def new(nil), do: nil
  def new(data) when is_map(data), do: Lingo.Type.Parse.fields(__MODULE__, data)
end
