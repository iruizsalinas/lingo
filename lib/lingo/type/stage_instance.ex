defmodule Lingo.Type.StageInstance do
  @moduledoc false

  @type privacy_level :: :guild_only

  @type t :: %__MODULE__{
          id: String.t(),
          guild_id: String.t(),
          channel_id: String.t(),
          topic: String.t(),
          privacy_level: privacy_level(),
          guild_scheduled_event_id: String.t() | nil
        }

  defstruct [
    :id,
    :guild_id,
    :channel_id,
    :topic,
    :guild_scheduled_event_id,
    privacy_level: :guild_only
  ]

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      guild_id: data["guild_id"],
      channel_id: data["channel_id"],
      topic: data["topic"],
      privacy_level: :guild_only,
      guild_scheduled_event_id: data["guild_scheduled_event_id"]
    }
  end
end
