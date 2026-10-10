defmodule Lingo.Event.ThreadDelete do
  @moduledoc """
  The payload of `:thread_delete`. Discord sends only the thread's ids and
  type; `old` is the thread as cached, or `nil`.
  """

  alias Lingo.Type.{Channel, Codes}

  @type t :: %__MODULE__{
          id: String.t(),
          guild_id: String.t(),
          parent_id: String.t() | nil,
          type: Channel.channel_type() | integer(),
          old: Channel.t() | nil
        }

  defstruct [:id, :guild_id, :parent_id, :type, :old]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      guild_id: data["guild_id"],
      parent_id: data["parent_id"],
      type: Codes.name(:channel_type, data["type"])
    }
  end
end
