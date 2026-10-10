defmodule Lingo.Event.SoundboardSounds do
  @moduledoc """
  The payload of `:guild_soundboard_sounds_update` (several of a guild's
  sounds changed at once) and `:soundboard_sounds` (the answer to
  `Lingo.Gateway.request_soundboard_sounds/1`).
  """

  alias Lingo.Type.SoundboardSound

  @type t :: %__MODULE__{guild_id: String.t(), soundboard_sounds: [SoundboardSound.t()]}

  defstruct [:guild_id, soundboard_sounds: []]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      guild_id: data["guild_id"],
      soundboard_sounds: Lingo.Type.Parse.list(data["soundboard_sounds"], &SoundboardSound.new/1)
    }
  end
end
