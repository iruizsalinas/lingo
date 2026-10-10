defmodule Lingo.Event.MessageDelete do
  @moduledoc "The payload of `:message_delete`. `old` is the message as cached, or `nil`."

  alias Lingo.Type.Message

  @type t :: %__MODULE__{
          id: String.t(),
          channel_id: String.t(),
          guild_id: String.t() | nil,
          old: Message.t() | nil
        }

  defstruct [:id, :channel_id, :guild_id, :old]

  @doc false
  def new(nil), do: nil
  def new(data) when is_map(data), do: Lingo.Type.Parse.fields(__MODULE__, data)
end
