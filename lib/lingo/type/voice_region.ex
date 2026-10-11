defmodule Lingo.Type.VoiceRegion do
  @moduledoc """
  A voice region, whose `id` can be a voice or stage channel's `rtc_region`.
  `optimal` marks the closest one; avoid `deprecated` ones.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          optimal: boolean(),
          deprecated: boolean(),
          custom: boolean()
        }

  defstruct [:id, :name, optimal: false, deprecated: false, custom: false]

  @doc false
  def new(nil), do: nil
  def new(data) when is_map(data), do: Lingo.Type.Parse.fields(__MODULE__, data)
end
