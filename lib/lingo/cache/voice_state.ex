defmodule Lingo.Cache.VoiceState do
  @moduledoc "Cached voice states: who is in which voice channel. See `Lingo.Cache` for enabling and configuring the cache."

  alias Lingo.Cache.{Cluster, Tables}

  @doc """
  A user's voice state, while they're in a voice channel, or `nil`.
  `cluster: true` asks the node running the guild's shard on a miss.
  """
  @spec get(Lingo.Api.id(), Lingo.Api.id(), keyword()) :: Lingo.Type.VoiceState.t() | nil
  def get(guild_id, user_id, opts \\ []),
    do: Cluster.guild(guild_id, opts, Tables, :get, [:voice_states, {guild_id, user_id}])

  @doc "The voice states of everyone in a guild's voice channels. Takes `cluster: true` as `get/3` does."
  @spec list(Lingo.Api.id(), keyword()) :: [Lingo.Type.VoiceState.t()]
  def list(guild_id, opts \\ []) do
    Cluster.guild(guild_id, opts, Tables, :select, [
      :voice_states,
      [{{{guild_id, :_}, :"$1"}, [], [:"$1"]}]
    ])
  end
end
