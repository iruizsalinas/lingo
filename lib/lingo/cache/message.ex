defmodule Lingo.Cache.Message do
  @moduledoc "Recent messages. See `Lingo.Cache` for enabling and configuring the cache."

  alias Lingo.Cache.Tables

  @doc "A recent message, or `nil`."
  @spec get(Lingo.Api.id(), Lingo.Api.id()) :: Lingo.Type.Message.t() | nil
  def get(channel_id, message_id), do: Tables.get(:messages, {channel_id, message_id})

  @doc "A channel's cached messages, oldest first."
  @spec list(Lingo.Api.id()) :: [Lingo.Type.Message.t()]
  def list(channel_id) do
    :messages
    |> Tables.select([{{{channel_id, :_}, :"$1"}, [], [:"$1"]}])
    |> Enum.sort_by(&Lingo.Snowflake.to_integer(&1.id))
  end
end
