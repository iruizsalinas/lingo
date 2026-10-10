defmodule Lingo.Type.Overwrite do
  @moduledoc "A permission overwrite on a channel, for a `:role` or a `:member`."

  @type overwrite_type :: :role | :member

  @type t :: %__MODULE__{
          id: String.t(),
          type: overwrite_type(),
          allow: String.t(),
          deny: String.t()
        }

  defstruct [:id, :type, :allow, :deny]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      type: if(data["type"] == 0, do: :role, else: :member),
      allow: data["allow"] || "0",
      deny: data["deny"] || "0"
    }
  end
end
