defmodule Lingo.Event.ReactionRemoveAll do
  @moduledoc "The payload of `:message_reaction_remove_all`: every reaction on a message was removed."

  @type t :: %__MODULE__{
          channel_id: String.t(),
          message_id: String.t(),
          guild_id: String.t() | nil
        }

  defstruct [:channel_id, :message_id, :guild_id]

  @doc false
  def new(nil), do: nil
  def new(data) when is_map(data), do: Lingo.Type.Parse.fields(__MODULE__, data)
end
