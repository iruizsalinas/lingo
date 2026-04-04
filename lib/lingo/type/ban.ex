defmodule Lingo.Type.Ban do
  @moduledoc false

  alias Lingo.Type.User

  @type t :: %__MODULE__{
          reason: String.t() | nil,
          user: User.t()
        }

  defstruct [:reason, :user]

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      reason: data["reason"],
      user: User.new(data["user"])
    }
  end
end
