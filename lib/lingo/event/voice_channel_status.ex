defmodule Lingo.Event.VoiceChannelStatus do
  @moduledoc "The payload of `:voice_channel_status_update`. `id` is the channel's."

  @type t :: %__MODULE__{id: String.t(), guild_id: String.t(), status: String.t() | nil}

  defstruct [:id, :guild_id, :status]

  @doc false
  def new(nil), do: nil
  def new(data) when is_map(data), do: Lingo.Type.Parse.fields(__MODULE__, data)
end
