defmodule Lingo.Cache.Rest.Response do
  @moduledoc false
  alias Lingo.Cache.{Access, Merge, Tables}
  alias Lingo.Type

  @types %{
    guilds: Type.Guild,
    channels: Type.Channel,
    roles: Type.Role,
    users: Type.User,
    voice_states: Type.VoiceState,
    members: Type.Member,
    messages: Type.Message
  }

  def actions(_, :delete, key, _), do: [{:delete, key}]

  def actions(_, :voice_delete, {g, id}, _) do
    id = if id == "@me", do: Lingo.Instance.get(:user_id), else: id
    if id, do: [{:delete, {g, id}}], else: []
  end

  def actions(_, :bulk_delete, {channel, body}, _) do
    Enum.map(body[:messages] || body["messages"] || [], &{:delete, {channel, &1}})
  end

  def actions(_, :prune, spec, _), do: [{:prune, spec}]

  def actions(:roles, :guild_roles, context, data) do
    if is_map(data) and is_list(data["roles"]),
      do: actions(:roles, :roles, context, data["roles"]),
      else: []
  end

  def actions(name, :threads, context, data),
    do: actions(name, :put, context, data["threads"] || [])

  def actions(name, :pins, context, data),
    do: actions(name, :put, context, Enum.map(data["items"] || [], & &1["message"]))

  def actions(:users, :member_users, _, data) do
    data |> values() |> Enum.flat_map(&actions(:users, :one, %{}, &1["user"]))
  end

  def actions(:users, :message_users, _, data) do
    data |> values() |> Enum.flat_map(&actions(:users, :one, %{}, &1["author"]))
  end

  def actions(:messages, :guild_messages, guild_id, _) do
    channels = Tables.select(:channels, [{{:"$1", %{guild_id: guild_id}}, [], [:"$1"]}])

    [{:prune, [{{:_, %{guild_id: guild_id}}, [], [true]}]}] ++
      Enum.map(channels, &{:prune, [{{{&1, :_}, :_}, [], [true]}]})
  end

  def actions(:roles, :roles, %{"guild_id" => guild} = context, data) when is_list(data) do
    ids = Map.new(data, &{&1["id"], true})
    # Only this complete collection is authoritative; pages and searches never prune.
    prune = [{{{guild, :"$1"}, :_}, [{:not, {:is_map_key, :"$1", {:const, ids}}}], [true]}]
    [{:prune, prune} | actions(:roles, :put, context, data)]
  end

  def actions(name, mode, context, data) when mode in [:put, :one] do
    Enum.flat_map(values(data), fn raw ->
      raw = Map.merge(context, raw)
      raw = member_user(name, raw)
      key = key(name, raw)

      if key == nil do
        []
      else
        module = Map.fetch!(@types, name)
        existing = Tables.get(name, key)
        value = merge(existing, module, raw)

        value =
          if name == :guilds, do: %{value | channels: [], members: [], roles: []}, else: value

        if name == :voice_states and value.channel_id == nil,
          do: [{:delete, key}],
          else: [Access.prepare(Access.resource(name), name, {key, value})]
      end
    end)
  end

  def actions(_, _, _, _), do: []

  defp values(data) when is_list(data), do: Enum.filter(data, &is_map/1)
  defp values(data) when is_map(data), do: [data]
  defp values(_), do: []

  defp member_user(:members, %{"user" => %{"id" => _}} = raw), do: raw

  defp member_user(:members, raw) do
    id = if raw["user_id"] == "@me", do: Lingo.Instance.get(:user_id), else: raw["user_id"]
    if id, do: Map.put(raw, "user", %{"id" => id}), else: raw
  end

  defp member_user(_, raw), do: raw

  defp key(:members, %{"guild_id" => g, "user" => %{"id" => id}}) when g != nil and id != nil,
    do: {g, id}

  defp key(:members, _), do: nil

  defp key(:voice_states, %{"guild_id" => g, "user_id" => id}) when g != nil and id != nil do
    id = if id == "@me", do: Lingo.Instance.get(:user_id), else: id
    if id, do: {g, id}
  end

  defp key(:voice_states, _), do: nil
  defp key(:roles, %{"guild_id" => g, "id" => id}) when g != nil and id != nil, do: {g, id}
  defp key(:roles, _), do: nil
  defp key(:messages, %{"channel_id" => c, "id" => id}) when c != nil and id != nil, do: {c, id}
  defp key(:messages, _), do: nil
  defp key(_, raw), do: raw["id"]

  defp merge(nil, module, raw), do: module.new(raw)
  defp merge(%Type.Message{} = old, _, raw), do: Merge.message(old, raw)

  defp merge(old, module, raw) do
    parsed = module.new(raw)

    Enum.reduce(Map.keys(Map.from_struct(old)), old, fn field, acc ->
      if Map.has_key?(raw, Atom.to_string(field)),
        do: Map.put(acc, field, Map.get(parsed, field)),
        else: acc
    end)
    |> merge_member_user(old, parsed)
  end

  defp merge_member_user(
         %Type.Member{user: user} = member,
         %Type.Member{user: old},
         %Type.Member{}
       )
       when user != nil and old != nil,
       do: %{member | user: Merge.user(old, user)}

  defp merge_member_user(value, _, _), do: value
end
