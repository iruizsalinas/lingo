defmodule Lingo.Event.GuildBan do
  @moduledoc "The payload of `:guild_ban_add` and `:guild_ban_remove`."

  alias Lingo.Type.User

  @type t :: %__MODULE__{guild_id: String.t(), user: User.t()}

  defstruct [:guild_id, :user]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data),
    do: %__MODULE__{guild_id: data["guild_id"], user: User.new(data["user"])}
end
