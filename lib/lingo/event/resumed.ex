defmodule Lingo.Event.Resumed do
  @moduledoc """
  The payload of `:resumed`: a shard reconnected and resumed its session,
  replaying the events it missed.
  """

  @type t :: %__MODULE__{shard_id: non_neg_integer(), shard_count: pos_integer()}

  defstruct shard_id: 0, shard_count: 1

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    [shard_id, shard_count] = data["shard"] || [0, 1]
    %__MODULE__{shard_id: shard_id, shard_count: shard_count}
  end
end
