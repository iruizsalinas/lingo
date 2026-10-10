defmodule Lingo.Event.ChannelPinsUpdate do
  @moduledoc """
  The payload of `:channel_pins_update`: a message was pinned or unpinned.
  It's not sent when a pinned message is deleted.
  """

  alias Lingo.Type.Parse

  @type t :: %__MODULE__{
          guild_id: String.t() | nil,
          channel_id: String.t(),
          last_pin_timestamp: DateTime.t() | nil
        }

  defstruct [:guild_id, :channel_id, :last_pin_timestamp]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    struct(Parse.fields(__MODULE__, data),
      last_pin_timestamp: Parse.timestamp(data["last_pin_timestamp"])
    )
  end
end
