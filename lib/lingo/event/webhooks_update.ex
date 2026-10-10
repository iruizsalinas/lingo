defmodule Lingo.Event.WebhooksUpdate do
  @moduledoc "The payload of `:webhooks_update`: a channel's webhooks changed."

  @type t :: %__MODULE__{guild_id: String.t(), channel_id: String.t()}

  defstruct [:guild_id, :channel_id]

  @doc false
  def new(nil), do: nil
  def new(data) when is_map(data), do: Lingo.Type.Parse.fields(__MODULE__, data)
end
