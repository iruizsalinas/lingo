defmodule Lingo.Cache do
  @moduledoc """
  What the gateway and REST API have told the bot, read from ETS: cheap, and
  never contacting Discord. Each resource has a module, mirroring `Lingo.Api`:

      Lingo.Cache.Guild.get(guild_id)
      Lingo.Cache.Role.list(guild_id)
      Lingo.Cache.Member.get(guild_id, user_id)

  The resources are `Lingo.Cache.Guild`, `Lingo.Cache.Channel` (including
  threads and DMs), `Lingo.Cache.User`, `Lingo.Cache.Member`,
  `Lingo.Cache.Role`, `Lingo.Cache.Presence`, `Lingo.Cache.VoiceState` and
  `Lingo.Cache.Message`. Anything not cached reads as `nil` (or `[]`).

  ## Enabling

  Caching is opt-in: omitting `:cache`, `cache: []` and `cache: false` cache
  nothing. Enable resources with the `:cache` option of `Lingo.start_link/1`,
  each as `true` (its defaults), `false` or a keyword policy:

      cache: [
        users: true,
        members: [max_entries_per_guild: 500, keep: :self],
        messages: [max_entries: 10_000, max_entries_per_channel: 100,
                   ttl: :timer.minutes(15), compressed: true]
      ]

  Resource names are `:guilds`, `:channels`, `:users`, `:members`, `:roles`,
  `:presences`, `:voice_states` and `:messages`. `:users` and `:members` also
  accept `:self`, keeping only the bot's own entry. With `:only`, the listed
  resources are enabled and every other one is off: `cache: [only: [:messages]]`.

  The bot's own permission checks (`Lingo.Helper.*`) need:

      cache: [guilds: true, channels: true, roles: true, users: :self, members: :self]

  Checks involving another member need that member cached too;
  `Lingo.Helper.Member.fetch_permissions/2` and
  `Lingo.Helper.Channel.fetch_permissions/2` report what's missing.

  The cache doesn't change intents, request member chunks, fetch missing data
  or suppress events. Enable the matching intents to receive updates (member
  departures need `:guild_members`). Event callbacks still get their payloads;
  `old` is `nil` when its resource is disabled, filtered, expired or evicted.

  ## Policies

    * `:max_entries` - bounds the resource across the bot.
    * `:max_entries_per_guild` (channels, members, roles, presences, voice
      states) and `:max_entries_per_channel` (messages, default 200) - bound
      it per guild or channel. Global and scoped limits both apply. The oldest
      write is evicted first; updating an entry refreshes it.
    * `:ttl` - milliseconds since the last write, or `:infinity` (default).
      Reads don't refresh it. Expired entries vanish from reads at once and are
      removed in batches. TTL bounds retention, not freshness.
    * `:filter` - which entries to admit: `:all` (default), `:none`, `:self`
      (users, members) or `fn entry, context -> boolean end`. A rejected update
      removes the entry's previous version.
    * `:keep` - entries always admitted and never evicted or expired, with the
      same values as `:filter` (default `:none`). They count toward limits but
      may exceed them. Zero limits with `keep: :self` keep only the bot's own
      entry; zero limits without it disable the resource.
    * `:compact` (default `true`) - stores Discord structs without their default
      fields and rebuilds them on read. `false` skips that work for bigger values.
    * `:compressed` (default `false`) - OTP's ETS compression. Smaller, but
      reads and scans cost more; measure with your workload.

  `:compact` and `:compressed` can also be set for every resource at once, and
  resource settings override them: `cache: [compressed: true, messages: true,
  roles: [compressed: false]]`. They never enable a disabled resource.

  Predicates get the entry and a context with `:bot`, `:user_id` (the bot's,
  `nil` before READY), `:resource` and `:key`. Keys are `{guild_id, id}` for
  members, roles, presences and voice states, and `{channel_id, id}` for
  messages. Keep predicates fast and pure; one that raises rejects the entry.

  Discord deletions and `clear/1` remove kept entries too. Evicting or
  clearing a resource doesn't touch the others; members and presences keep
  their user even when the user cache is off or bounded.

  ## REST responses

  Successful REST calls refresh the enabled caches of the guilds, channels,
  roles, members, users, messages and voice states they return (users inside
  members and message authors only when the user cache is on), under the same
  policies. REST calls never read from the cache, and refreshes don't
  dispatch events.

    * A complete role list replaces that guild's cached roles, kept ones
      included. Paginated lists, searches, pins and thread lists only refresh
      the entries they return.
    * Guild previews and user guild summaries don't overwrite full guilds.
      Partial responses keep the fields they omit; explicit nulls and empty
      lists still apply.
    * Deleting a role, message, channel or guild removes it; kicking a member
      also removes their presence and voice state. Changes Discord answers
      without a full body, such as member roles and permission overwrites,
      drop the affected entries instead of guessing their new state.
    * If anything changes a resource while a request is in flight, the
      response is returned but its cache update is skipped, so a late response
      never overwrites newer data or brings back a deleted entry. This can
      also skip a refresh after an unrelated change.

  ## Legacy options

  `:enabled` and `:max_messages_per_channel` still work; prefer `:only` and
  `messages: [max_entries_per_channel: ...]`. `:max_messages_per_channel`
  enables messages unless they're disabled or left out of `:only`/`:enabled`.
  `:permissions` enables guilds, channels, roles and the bot's own user and
  member.
  """

  alias Lingo.Cache.Tables

  @doc """
  The cache's footprint and policies, by resource: entry counts (expired
  entries awaiting cleanup included), kept entries, ETS memory in bytes with
  indexes, and how far kept entries push past limits.

  ETS memory isn't total VM memory: it leaves out process state and shared
  binaries, so measure the VM too when comparing policies.
  """
  @spec stats() :: map()
  def stats, do: Tables.stats()

  @doc """
  Empties one resource, or every resource by default, kept entries included.
  Policies and the bot's own user stay; nothing is treated as a Discord deletion.
  """
  @spec clear(atom()) :: :ok
  def clear(resource \\ :all), do: Tables.clear(resource)
end
