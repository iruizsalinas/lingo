defmodule Lingo.Type.LobbyMember do
  @moduledoc """
  A member of a `Lingo.Type.Lobby`. `id` is the user's id; `can_link_lobby?/1`
  says whether they may link the lobby to a channel.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          metadata: %{String.t() => String.t()} | nil,
          flags: integer()
        }

  defstruct [:id, :metadata, flags: 0]

  @doc false
  def new(nil), do: nil
  def new(data) when is_map(data), do: Lingo.Type.Parse.fields(__MODULE__, data)

  @doc "Whether the member may link the lobby to a channel."
  @spec can_link_lobby?(t()) :: boolean()
  def can_link_lobby?(%__MODULE__{flags: flags}), do: Bitwise.band(flags, 1) != 0
end
