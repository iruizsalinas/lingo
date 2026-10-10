defmodule Lingo.Cache.VoiceState do
  @moduledoc "Cached voice states: who is in which voice channel. See `Lingo.Cache` for enabling and configuring the cache."

  alias Lingo.Cache.Tables

  @doc "A user's voice state, while they're in a voice channel, or `nil`."
  @spec get(Lingo.Api.id(), Lingo.Api.id()) :: Lingo.Type.VoiceState.t() | nil
  def get(guild_id, user_id), do: Tables.get(:voice_states, {guild_id, user_id})

  @doc "The voice states of everyone in a guild's voice channels."
  @spec list(Lingo.Api.id()) :: [Lingo.Type.VoiceState.t()]
  def list(guild_id), do: Tables.select(:voice_states, [{{{guild_id, :_}, :"$1"}, [], [:"$1"]}])
end
