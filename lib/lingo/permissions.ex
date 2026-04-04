defmodule Lingo.Permissions do
  @moduledoc false

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
    send_polls: 1 <<< 49,
    use_external_apps: 1 <<< 50,
    pin_messages: 1 <<< 51,
    bypass_slowmode: 1 <<< 52
  }

  @type permission :: atom()

  @spec has?(String.t() | integer(), permission()) :: boolean()
  def has?(bitfield, permission) when is_binary(bitfield) do
    has?(String.to_integer(bitfield), permission)
  end

  def has?(bitfield, permission) when is_integer(bitfield) and is_atom(permission) do
    flag = Map.fetch!(@permissions, permission)
    Bitwise.band(bitfield, flag) == flag
  end

  @spec has_all?(String.t() | integer(), [permission()]) :: boolean()
  def has_all?(bitfield, permissions) do
    Enum.all?(permissions, &has?(bitfield, &1))
  end

  @spec has_any?(String.t() | integer(), [permission()]) :: boolean()
  def has_any?(bitfield, permissions) do
    Enum.any?(permissions, &has?(bitfield, &1))
  end

  @spec resolve([permission()]) :: integer()
  def resolve(permissions) when is_list(permissions) do
    Enum.reduce(permissions, 0, fn perm, acc ->
      Bitwise.bor(acc, Map.fetch!(@permissions, perm))
    end)
  end

  @spec to_list(String.t() | integer()) :: [permission()]
  def to_list(bitfield) when is_binary(bitfield), do: to_list(String.to_integer(bitfield))

  def to_list(bitfield) when is_integer(bitfield) do
    @permissions
    |> Enum.filter(fn {_name, flag} -> Bitwise.band(bitfield, flag) == flag end)
    |> Enum.map(&elem(&1, 0))
  end

  @spec all_permissions :: [permission()]
  def all_permissions, do: Map.keys(@permissions)

  @admin_flag @permissions[:administrator]
  @all_flags Enum.reduce(@permissions, 0, fn {_, v}, acc -> bor(acc, v) end)

  @spec compute(
          base_permissions :: String.t() | integer(),
          member_role_ids :: [String.t()],
          roles :: [%{id: String.t(), permissions: String.t()}],
          channel_overwrites :: [
            %{id: String.t(), type: :role | :member, allow: String.t(), deny: String.t()}
          ],
          member_id :: String.t() | nil
        ) :: integer()
  def compute(everyone_perms, member_role_ids, roles, overwrites \\ [], member_id \\ nil) do
    base = parse_bitfield(everyone_perms)

    base =
      roles
      |> Enum.filter(fn r -> r.id in member_role_ids end)
      |> Enum.reduce(base, fn r, acc -> bor(acc, parse_bitfield(r.permissions)) end)

    if band(base, @admin_flag) == @admin_flag do
      @all_flags
    else
      apply_overwrites(base, member_role_ids, overwrites, member_id)
    end
  end

  defp apply_overwrites(perms, _role_ids, [], _member_id), do: perms

  defp apply_overwrites(perms, role_ids, overwrites, member_id) do
    # @everyone overwrite (id == guild_id, which is the first role)
    everyone_ow = Enum.find(overwrites, fn ow -> ow.type == :role and ow.id not in role_ids end)

    perms =
      if everyone_ow do
        perms
        |> band(bnot(parse_bitfield(everyone_ow.deny)))
        |> bor(parse_bitfield(everyone_ow.allow))
      else
        perms
      end

    # role overwrites
    role_ows = Enum.filter(overwrites, fn ow -> ow.type == :role and ow.id in role_ids end)

    {role_allow, role_deny} =
      Enum.reduce(role_ows, {0, 0}, fn ow, {a, d} ->
        {bor(a, parse_bitfield(ow.allow)), bor(d, parse_bitfield(ow.deny))}
      end)

    perms = perms |> band(bnot(role_deny)) |> bor(role_allow)

    # member overwrite
    if member_id do
      case Enum.find(overwrites, fn ow -> ow.type == :member and ow.id == member_id end) do
        nil ->
          perms

        ow ->
          perms
          |> band(bnot(parse_bitfield(ow.deny)))
          |> bor(parse_bitfield(ow.allow))
      end
    else
      perms
    end
  end

  defp parse_bitfield(v) when is_integer(v), do: v
  defp parse_bitfield(v) when is_binary(v), do: String.to_integer(v)
  defp parse_bitfield(nil), do: 0
end
