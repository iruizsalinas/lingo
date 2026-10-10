defmodule Lingo.Cache do
  @moduledoc """
  What the gateway and REST API have told the bot about guilds, channels, users, members,
  roles, presences, voice states and recent messages.

  Successful REST responses also refresh enabled caches for guilds, channels
  (including threads and DMs), roles, members, users, messages and voice states.
  Embedded member users and message authors refresh the independent user cache
  only when enabled. Policies apply to REST writes exactly as to gateway writes.
  REST calls never read from the cache instead of making their HTTP request.

  A complete role list reconciles that guild's cached roles, removing entries
  missing from the response, including kept entries. Paginated lists, searches,
  pins and thread lists only refresh returned entries. Guild previews and user
  guild summaries do not overwrite full guild records. Partial responses preserve
  fields they omit; explicit nulls and empty collections still update those fields.
  Successful role, message, channel and guild deletions invalidate cached data;
  member kicks also remove cached presence and voice state. Mutations without a
  full response, such as member role changes and channel permission overwrites,
  invalidate affected entries rather than inventing a new resource state.

  REST refreshes use a conservative per-resource revision check. If any write,
  deletion, clear, or expiration cleanup changes that resource after a request
  starts, its response is returned normally but its cache update is skipped.
  This can skip a refresh after an unrelated entry changes; it prevents delayed
  responses from overwriting newer observed data or resurrecting deleted entries.
  Cache restarts invalidate outstanding refreshes too. Disabled resources skip
  tracking and cache-only response parsing, predicates and traversal. Cache
  refreshes do not dispatch gateway events.

  Reads are ETS lookups, so they're cheap and never touch Discord. Anything
  not cached returns `nil` (or `[]`). Configure policies with the `:cache`
  option of `Lingo.start_link/1`:

      cache: [
        compact: true,
        compressed: false,
        users: true,
        members: [filter: :all, max_entries_per_guild: 500, keep: :self],
        messages: [max_entries: 10_000, max_entries_per_channel: 100,
                   ttl: :timer.minutes(15), compressed: true]
      ]

  Resources are `:guilds`, `:channels` (including threads), `:users`, `:members`,
  `:roles`, `:presences`, `:voice_states` and `:messages`. Each accepts `false`,
  `true` for its defaults, or a keyword policy. Users and members also accept
  `:self`, retaining only the bot itself. `cache: false` disables all resource
  caches. Omitting `:cache`, or passing `cache: []`, disables all resource caches.
  Only explicitly enabled resources are retained; no preset name is needed.

  Keyword policies enable their resource with normal policy defaults
  (`filter: :all`, `keep: :none`). Use `:self` for users or members when only
  the bot's own entry is needed.
  For example, `messages: [ttl: 60_000]` enables messages with a 60-second TTL
  and the normal 200-per-channel limit. Other limits and TTLs default to
  `:infinity`. With `:only`, listed resources are enabled unless explicitly
  disabled, and all other resources are excluded. For example,
  `cache: [only: [:messages]]` caches messages alone.

  `:compact` and `:compressed` also accept global settings inside `:cache`:

      cache: [compressed: true, messages: true, roles: [compressed: false]]

  Storage precedence is library defaults, then global settings, then resource
  overrides. Global storage settings never enable disabled resources. Limits,
  TTLs and predicates are per resource.

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
    * `:compact` defaults to `true`. Storage omits default-valued fields of known
      Discord structs, including nested values. Reads reconstruct complete structs;
      predicates and events receive complete structs too. Set `false` to avoid
      this encoding/decoding work at the cost of larger stored values.
    * `:compressed` defaults to `false`. Set `true` to enable OTP's ETS compression
      for that resource, for example `messages: [compressed: true]`. Compression
      can reduce memory further but makes reads and scans more expensive. It can
      be combined with either compact setting; measure with your own workload.

  Predicate context contains `:bot` (instance name), `:user_id` (bot ID, possibly
  nil before READY), `:resource` and `:key`. Keys match the resource's lookup:
  member/role/presence/voice-state keys are `{guild_id, id}`, message keys are
  `{channel_id, id}`. Predicates should be fast and pure; failures reject the
  entry and do not suppress event callbacks. Ordinary entries are evicted by
  oldest write, so updating an entry refreshes its eviction order.

  Discord deletions and `clear/1` remove kept entries too. Capacity eviction
  and clearing a parent resource do not delete other resource caches. Members
  and presences retain user data even when the user cache is disabled or bounded.

  To support the bot's own permission checks, explicitly enable the required caches:

      cache: [guilds: true, channels: true, roles: true, users: :self, members: :self]

  Checks require the data to have arrived; checks involving another member
  still need that member to be cached. Detailed
  helpers `Lingo.Helper.Member.fetch_permissions/2` and
  `Lingo.Helper.Channel.fetch_permissions_for/2` report missing data explicitly.
  The single current-user identity record is internal bot state and survives
  disabling or clearing caches.

  Cache policy does not change intents, request member chunks, fetch missing
  data, or suppress gateway events. Callback payloads are still parsed; `old`
  may be nil when its resource is disabled, filtered, expired or evicted.
  Disabled resources skip cache-only parsing/traversal and allocate no resource
  tables or indexes. Enabled caches serialize writes per bot so REST revision
  checks and mutations are atomic across shards and callers. Reads use ETS.
  TTL maintenance exists only when configured.

  Eviction indexes exist only for configured global or scoped limits, and an
  expiration index exists only for TTL. Scans requiring expiration checks or
  reconstruction copy candidates in bounded batches. Returned lists still use
  memory proportional to the result. ETS tables and their representation are
  internal; use this module's reads rather than accessing raw table contents.

  Enable the corresponding gateway intents for updates; in particular, member
  departure cleanup needs `:guild_members`. TTL bounds retention, not freshness.
  Legacy `:enabled` and `:max_messages_per_channel` remain accepted; use `:only`
  and `messages: [max_entries_per_channel: ...]` in new configurations.
  The legacy `:permissions` value explicitly enables guilds, channels, roles
  and the bot's own user/member.
  Legacy `:max_messages_per_channel` implicitly enables messages unless they
  are explicitly disabled or excluded by `:only`/`:enabled`.
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
    # Prefer the latest independently cached user over the retained fallback.
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
  ETS memory is not total VM memory: it excludes owner-process state and shared
  reference-counted binary payloads. Use VM/process measurements alongside these
  statistics when comparing storage policies.
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
