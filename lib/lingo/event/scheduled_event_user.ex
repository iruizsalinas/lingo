defmodule Lingo.Event.ScheduledEventUser do
  @moduledoc """
  The payload of `:guild_scheduled_event_user_add` and
  `:guild_scheduled_event_user_remove`: a user subscribed to a scheduled
  event, or stopped.
  """

  @type t :: %__MODULE__{
          guild_scheduled_event_id: String.t(),
          user_id: String.t(),
          guild_id: String.t()
        }

  defstruct [:guild_scheduled_event_id, :user_id, :guild_id]

  @doc false
  def new(nil), do: nil
  def new(data) when is_map(data), do: Lingo.Type.Parse.fields(__MODULE__, data)
end
