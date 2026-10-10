defmodule Lingo.Type.Reaction do
  @moduledoc "The reactions with one emoji on a message."

  alias Lingo.Type.Emoji

  @type t :: %__MODULE__{
          count: integer(),
          count_details: map(),
          me: boolean(),
          me_burst: boolean(),
          emoji: Emoji.t(),
          burst_colors: [String.t()]
        }

  defstruct [
    :emoji,
    :count_details,
    count: 0,
    me: false,
    me_burst: false,
    burst_colors: []
  ]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      count: data["count"] || 0,
      count_details: data["count_details"],
      me: data["me"] || false,
      me_burst: data["me_burst"] || false,
      emoji: Emoji.new(data["emoji"]),
      burst_colors: data["burst_colors"] || []
    }
  end
end
