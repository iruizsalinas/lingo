defmodule Lingo.Permissions do
  @moduledoc """
  Permission bitfields.

  Discord sends permissions as bitfields (often as strings). These functions
  check and build them using atoms like `:send_messages` and `:ban_members`.

      Lingo.Permissions.has?(member_permissions, :manage_messages)
      Lingo.Permissions.from_list([:view_channel, :send_messages])
      #=> 3072
  """

  import Bitwise

  @permissions %{
    create_instant_invite: 1 <<< 0,
    kick_members: 1 <<< 1,
    ban_members: 1 <<< 2,
    administrator: 1 <<< 3,
    manage_channels: 1 <<< 4,
    manage_guild: 1 <<< 5,
    add_reactions: 1 <<< 6,
    view_audit_log: 1 <<< 7,
    priority_speaker: 1 <<< 8,
    stream: 1 <<< 9,
    view_channel: 1 <<< 10,
    send_messages: 1 <<< 11,
    send_tts_messages: 1 <<< 12,
    manage_messages: 1 <<< 13,
    embed_links: 1 <<< 14,
    attach_files: 1 <<< 15,
    read_message_history: 1 <<< 16,
    mention_everyone: 1 <<< 17,
    use_external_emojis: 1 <<< 18,
    view_guild_insights: 1 <<< 19,
    connect: 1 <<< 20,
    speak: 1 <<< 21,
    mute_members: 1 <<< 22,
    deafen_members: 1 <<< 23,
    move_members: 1 <<< 24,
    use_vad: 1 <<< 25,
    change_nickname: 1 <<< 26,
    manage_nicknames: 1 <<< 27,
    manage_roles: 1 <<< 28,
    manage_webhooks: 1 <<< 29,
    manage_guild_expressions: 1 <<< 30,
    use_application_commands: 1 <<< 31,
    request_to_speak: 1 <<< 32,
    manage_events: 1 <<< 33,
    manage_threads: 1 <<< 34,
    create_public_threads: 1 <<< 35,
    create_private_threads: 1 <<< 36,
    use_external_stickers: 1 <<< 37,
    send_messages_in_threads: 1 <<< 38,
    use_embedded_activities: 1 <<< 39,
    moderate_members: 1 <<< 40,
    view_creator_monetization_analytics: 1 <<< 41,
    use_soundboard: 1 <<< 42,
    create_guild_expressions: 1 <<< 43,
    create_events: 1 <<< 44,
    use_external_sounds: 1 <<< 45,
    send_voice_messages: 1 <<< 46,
    set_voice_channel_status: 1 <<< 48,
    send_polls: 1 <<< 49,
    use_external_apps: 1 <<< 50,
    pin_messages: 1 <<< 51,
    bypass_slowmode: 1 <<< 52
  }

  @type permission :: atom()

  @doc "Whether the bitfield includes `permission`. Administrator doesn't imply anything here; use `compute/5` for effective permissions."
  @spec has?(String.t() | integer(), permission()) :: boolean()
  def has?(bitfield, permission) when is_binary(bitfield) do
    has?(String.to_integer(bitfield), permission)
  end

  def has?(bitfield, permission) when is_integer(bitfield) and is_atom(permission) do
    flag = Map.fetch!(@permissions, permission)
    Bitwise.band(bitfield, flag) == flag
  end

  @doc "Whether the bitfield includes every one of `permissions`."
  @spec has_all?(String.t() | integer(), [permission()]) :: boolean()
  def has_all?(bitfield, permissions) do
    Enum.all?(permissions, &has?(bitfield, &1))
  end

  @doc "Whether the bitfield includes at least one of `permissions`."
  @spec has_any?(String.t() | integer(), [permission()]) :: boolean()
  def has_any?(bitfield, permissions) do
    Enum.any?(permissions, &has?(bitfield, &1))
  end

  @doc "Combines permission atoms (and raw bits) into a bitfield."
  @spec from_list([permission()]) :: integer()
  def from_list(permissions) when is_list(permissions) do
    Enum.reduce(permissions, 0, fn
      # raw bits allow permissions Lingo doesn't know about yet
      bits, acc when is_integer(bits) -> Bitwise.bor(acc, bits)
      perm, acc -> Bitwise.bor(acc, Map.fetch!(@permissions, perm))
    end)
  end

  @doc "The permission atoms set in a bitfield."
  @spec to_list(String.t() | integer()) :: [permission()]
  def to_list(bitfield) when is_binary(bitfield), do: to_list(String.to_integer(bitfield))

  def to_list(bitfield) when is_integer(bitfield) do
    @permissions
    |> Enum.filter(fn {_name, flag} -> Bitwise.band(bitfield, flag) == flag end)
    |> Enum.map(&elem(&1, 0))
  end

  @spec all() :: [permission()]
  @doc "Every permission atom Lingo knows."
  def all, do: Map.keys(@permissions)

  @spec compute(
          base_permissions :: String.t() | integer(),
          member_role_ids :: [String.t()],
          roles :: [%{id: String.t(), permissions: String.t()}],
          channel_overwrites :: [
            %{id: String.t(), type: :role | :member, allow: String.t(), deny: String.t()}
          ],
          member_id :: String.t() | nil
        ) :: integer()
  @doc """
  Effective permissions of a member in a channel: the `@everyone` role's
  permissions, plus their roles', then the channel's overwrites for
  `@everyone`, their roles and them. Administrators get everything.

  `roles` are the guild's `Lingo.Type.Role` structs and `overwrites` the
  channel's `Lingo.Type.Overwrite` structs. `Lingo.Helper.Channel.permissions/2`
  does this from the cache.
  """
  defdelegate compute(everyone_perms, member_role_ids, roles, overwrites \\ [], member_id \\ nil),
    to: Lingo.Permissions.Effective

  @doc false
  def flag(permission), do: Map.fetch!(@permissions, permission)

  @doc false
  def all_flags, do: Enum.reduce(@permissions, 0, fn {_, v}, acc -> bor(acc, v) end)
end
