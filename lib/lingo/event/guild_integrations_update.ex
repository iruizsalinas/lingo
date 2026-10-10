defmodule Lingo.Event.GuildIntegrationsUpdate do
  @moduledoc "The payload of `:guild_integrations_update`: a guild's integrations changed."

  @type t :: %__MODULE__{guild_id: String.t()}

  defstruct [:guild_id]

  @doc false
  def new(nil), do: nil
  def new(data) when is_map(data), do: %__MODULE__{guild_id: data["guild_id"]}
end
