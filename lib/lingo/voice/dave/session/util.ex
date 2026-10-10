defmodule Lingo.Voice.Dave.Session.Util do
  @moduledoc false

  # Small helpers shared by the session modules.

  alias Lingo.MLS.{Group, LeafNode}

  def users(group), do: Enum.map(Group.roster(group), fn {_index, leaf} -> user_id(leaf) end)

  def unique_users?(group), do: length(Enum.uniq(users(group))) == length(users(group))

  def user_id(%LeafNode{credential: {:basic, <<user_id::64>>}}), do: user_id
  def user_id(_leaf), do: nil

  def encode(iodata), do: IO.iodata_to_binary(iodata)

  def check(true, _reason), do: :ok
  def check(false, reason), do: {:error, reason}

  def fetch(nil, reason), do: {:error, reason}
  def fetch(value, _reason), do: {:ok, value}
end
