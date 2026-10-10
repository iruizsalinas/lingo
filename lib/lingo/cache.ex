defmodule Lingo.Cache do
  @moduledoc """
  What the gateway has told the bot about guilds, channels, users, members,
  roles, presences, voice states and recent messages.

  Reads are ETS lookups, so they're cheap and never touch Discord. Anything
  not cached returns `nil` (or `[]`). Configure policies with the `:cache`
  option of `Lingo.start_link/1`:

      cache: [
        guilds: true,
        channels: true,
        roles: true,
        users: [max_entries: 20_000, keep: :self],
        members: [max_entries_per_guild: 500, keep: :self],
        messages: [max_entries: 10_000, max_entries_per_channel: 100,
                   ttl: :timer.minutes(15)],
        presences: false
      ]

  Resources are `:guilds`, `:channels` (including threads), `:users`, `:members`,
  `:roles`, `:presences`, `:voice_states` and `:messages`. Each accepts `false`,
  `true` for its defaults, or a keyword policy. Users and members also accept
  `:self`, retaining only the bot itself. `cache: false` disables all resource
  caches. `:only` provides an allowlist; omitted resources otherwise use defaults.
  By default everything is cached, with 200 messages per channel; other limits
  and TTLs default to `:infinity`.

  Policies:

    * `:max_entries` bounds the resource across this bot.
    * `:max_entries_per_channel` applies to messages; `:max_entries_per_guild`
      applies to channels, members, roles, presences and voice states. Both
      global and scoped limits apply when configured.
    * `:ttl` is milliseconds since the last write, or `:infinity`. Reads do not
      refresh it. Expired entries disappear from reads immediately and are
      physically removed in batches. Limits count entries, not bytes.
    * `:filter` accepts `:all` (default), `:none`, `:self` (users/members), or
      `fn entry, context -> boolean end` to decide admission. A rejected update
      removes its previous cached entry.
    * `:keep` accepts the same values, defaulting to `:none`. Matching entries
      are always admitted and exempt from TTL and capacity eviction. They count
      toward limits but may exceed them. Zero limits with `keep: :self` retain
      only self; zero limits without `:keep` disable the resource.

  Predicate context contains `:bot` (instance name), `:user_id` (bot ID, possibly
  nil before READY), `:resource` and `:key`. Keys match the resource's lookup:
  member/role/presence/voice-state keys are `{guild_id, id}`, message keys are
  `{channel_id, id}`. Predicates should be fast and pure; failures reject the
  entry and do not suppress event callbacks. Ordinary entries are evicted by
  oldest write, so updating an entry refreshes its eviction order.

  Discord deletions and `clear/1` remove kept entries too. Capacity eviction
  and clearing a parent resource do not delete other resource caches. Members
  and presences retain user data even when the user cache is disabled or bounded.

  `cache: :permissions` retains guilds, channels, roles and only the bot's user
  and member. It supports the bot's own permission checks when that data has
  arrived; checks involving another member still need that member. Detailed
  helpers `Lingo.Helper.Member.fetch_permissions/2` and
  `Lingo.Helper.Channel.fetch_permissions_for/2` report missing data explicitly.
  The single current-user identity record is internal bot state and survives
  disabling or clearing caches.

  Cache policy does not change intents, request member chunks, fetch missing
  data, or suppress gateway events. Callback payloads are still parsed; `old`
  may be nil when its resource is disabled, filtered, expired or evicted.
  Disabled resources skip cache-only parsing/traversal and allocate no resource
  tables or indexes. Unlimited policies use direct ETS writes; managed policies
  serialize writes per bot for consistent limits across shards. Reads use ETS.
  TTL maintenance exists only when configured.

  Enable the corresponding gateway intents for updates; in particular, member
  departure cleanup needs `:guild_members`. TTL bounds retention, not freshness.
  Legacy `:enabled` and `:max_messages_per_channel` remain accepted; use `:only`
  and `messages: [max_entries_per_channel: ...]` in new configurations.
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
  def get_current_user, do: Tables.current_user()

  @doc "A guild member, with their user."
  @spec get_member(String.t(), String.t()) :: Member.t() | nil
  def get_member(guild_id, user_id) do
    # users are stored once, in their own table
    case Tables.get(:members, {guild_id, user_id}) do
      nil -> nil
      member -> %{member | user: get_user(user_id) || member.user}
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
      presence -> %{presence | user: get_user(user_id) || presence.user || %User{id: user_id}}
    end
  end

  @doc "A user's voice state, while they're in a voice channel."
  @spec get_voice_state(String.t(), String.t()) :: VoiceState.t() | nil
  def get_voice_state(guild_id, user_id), do: Tables.get(:voice_states, {guild_id, user_id})

  @doc """
  Cache footprint and normalized policies, keyed by resource. Includes physical
  entry counts (expired entries await cleanup), kept entries, ETS memory in bytes
  including indexes, and global/scoped capacity overflow caused by kept entries.
  The single current-user identity record is internal state and is excluded.
  """
  @spec stats() :: map()
  def stats, do: Tables.stats()

  @doc """
  Clears one resource, or all resource caches by default, including kept entries.
  Does not erase the bot's current-user identity or change configured policies.
  Clearing or evicting a resource does not simulate a Discord deletion.
  """
  @spec clear(atom()) :: :ok
  def clear(resource \\ :all), do: Tables.clear(resource)
end
