defmodule Lingo.Event.GuildDelete do
  @moduledoc """
  The payload of `:guild_delete`. `unavailable` is `true` when the guild is
  down in an outage (it comes back with a `:guild_create`), and `false` when
  the bot left or was removed. `old` is the guild as cached, or `nil`.
  """

  alias Lingo.Type.Guild

  @type t :: %__MODULE__{id: String.t(), unavailable: boolean(), old: Guild.t() | nil}

  defstruct [:id, :old, unavailable: false]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data),
    do: %__MODULE__{id: data["id"], unavailable: data["unavailable"] == true}
end
