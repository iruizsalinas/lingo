defmodule Lingo.Permissions.Effective do
  @moduledoc false

  # A member's permissions in a channel: the base from their roles, then the
  # channel's overwrites for @everyone, their roles and them, in that order.

  import Bitwise

  def compute(everyone_perms, member_role_ids, roles, overwrites, member_id) do
    base = parse_bitfield(everyone_perms)
    member_role_ids = role_id_map(member_role_ids)

    base =
      roles
      |> Enum.reduce(base, fn role, acc ->
        if Map.has_key?(member_role_ids, role.id) do
          bor(acc, parse_bitfield(role.permissions))
        else
          acc
        end
      end)

    if band(base, Lingo.Permissions.flag(:administrator)) != 0 do
      Lingo.Permissions.all_flags()
    else
      guild_id = everyone_role_id(roles)
      apply_overwrites(base, guild_id, member_role_ids, overwrites, member_id)
    end
  end

  defp everyone_role_id(roles) do
    case Enum.find(roles, fn r -> r.position == 0 end) do
      nil -> nil
      role -> role.id
    end
  end

  defp apply_overwrites(perms, _guild_id, _role_ids, [], _member_id), do: perms

  defp apply_overwrites(perms, guild_id, role_ids, overwrites, member_id) do
    # @everyone overwrite (id == guild_id)
    everyone_ow = Enum.find(overwrites, fn ow -> ow.type == :role and ow.id == guild_id end)

    perms =
      if everyone_ow do
        perms
        |> band(bnot(parse_bitfield(everyone_ow.deny)))
        |> bor(parse_bitfield(everyone_ow.allow))
      else
        perms
      end

    # role overwrites
    {role_allow, role_deny} =
      Enum.reduce(overwrites, {0, 0}, fn ow, {allow, deny} ->
        if ow.type == :role and Map.has_key?(role_ids, ow.id) do
          {bor(allow, parse_bitfield(ow.allow)), bor(deny, parse_bitfield(ow.deny))}
        else
          {allow, deny}
        end
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

  defp role_id_map(role_ids) do
    Map.new(role_ids, &{&1, true})
  end
end
