defmodule Lingo.Cache do
  @moduledoc """
  What the gateway has told the bot about guilds, channels, users, members,
  roles, presences, voice states and recent messages.

  Reads are ETS lookups, so they're cheap and never touch Discord. Anything
  not cached returns `nil` (or `[]`). Which resources are cached, and how many
  messages per channel, is set with the `:cache` option of `Lingo.start_link/1`.
  Members, presences and messages also need their gateway intents.
  """

  alias Lingo.Cache.Tables
  alias Lingo.Type.{Channel, Guild, Member, Message, Presence, Role, User, VoiceState}

  @doc "A guild."
  @spec get_guild(String.t()) :: Guild.t() | nil
  def get_guild(id), do: Tables.get(:guilds, id)

  @doc "Every cached guild."
  @spec list_guilds() :: [Guild.t()]
  def list_guilds, do: Tables.select(:guilds, [{{:_, :"$1"}, [], [:"$1"]}])

  @doc "A channel or thread."
  @spec get_channel(String.t()) :: Channel.t() | nil
  def get_channel(id), do: Tables.get(:channels, id)

  @doc "A user."
  @spec get_user(String.t()) :: User.t() | nil
  def get_user(id), do: Tables.get(:users, id)

  @doc "The bot's own user, once the first shard is ready."
  @spec get_current_user() :: User.t() | nil
  def get_current_user, do: Tables.get(:users, :me)

  @doc "A guild member, with their user."
  @spec get_member(String.t(), String.t()) :: Member.t() | nil
  def get_member(guild_id, user_id) do
    # users are stored once, in their own table
    case Tables.get(:members, {guild_id, user_id}) do
      nil -> nil
      member -> %{member | user: get_user(user_id)}
    end
  end

  @doc "A role."
  @spec get_role(String.t(), String.t()) :: Role.t() | nil
  def get_role(guild_id, role_id), do: Tables.get(:roles, {guild_id, role_id})

  @doc "A guild's roles."
  @spec list_roles(String.t()) :: [Role.t()]
  def list_roles(guild_id), do: Tables.select(:roles, [{{{guild_id, :_}, :"$1"}, [], [:"$1"]}])

  @doc "A recent message."
  @spec get_message(String.t(), String.t()) :: Message.t() | nil
  def get_message(channel_id, message_id), do: Tables.get(:messages, {channel_id, message_id})

  @doc "A member's presence."
  @spec get_presence(String.t(), String.t()) :: Presence.t() | nil
  def get_presence(guild_id, user_id) do
    case Tables.get(:presences, {guild_id, user_id}) do
      nil -> nil
      presence -> %{presence | user: get_user(user_id) || %User{id: user_id}}
    end
  end

  @doc "A user's voice state, while they're in a voice channel."
  @spec get_voice_state(String.t(), String.t()) :: VoiceState.t() | nil
  def get_voice_state(guild_id, user_id), do: Tables.get(:voice_states, {guild_id, user_id})
end
