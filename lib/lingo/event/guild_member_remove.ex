defmodule Lingo.Event.GuildMemberRemove do
  @moduledoc """
  The payload of `:guild_member_remove`: a user left, or was kicked or
  banned. `old` is the member as cached, or `nil`.
  """

  alias Lingo.Type.{Member, User}

  @type t :: %__MODULE__{guild_id: String.t(), user: User.t(), old: Member.t() | nil}

  defstruct [:guild_id, :user, :old]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data),
    do: %__MODULE__{guild_id: data["guild_id"], user: User.new(data["user"])}
end
