defmodule Lingo.Cache.Store do
  @moduledoc false

  # Writes to the cache, from gateway events. Members, presences, roles and
  # voice states are keyed {guild_id, id}, messages {channel_id, id} in an
  # ordered set; users are stored once and joined back in on reads.

  alias Lingo.Cache
  alias Lingo.Cache.{Merge, Tables}

  def put_guild(%{id: id} = guild), do: Tables.insert(:guilds, {id, guild})

  # a guild takes everything in it along
  def delete_guild(id) do
    Tables.delete(:guilds, id)

    for resource <- [:members, :roles, :presences, :voice_states],
        do: delete_by_guild(resource, id)

    channel_ids = Tables.select(:channels, [{{:"$1", %{guild_id: id}}, [], [:"$1"]}])
    Enum.each(channel_ids, &delete_channel/1)
  end

  def put_channel(%{id: id} = channel), do: Tables.insert(:channels, {id, channel})

  def delete_channel(id) do
    Tables.delete(:channels, id)
    Tables.select_delete(:messages, [{{{id, :_}, :_}, [], [true]}])
  end

  def put_user(%{id: id} = user), do: Tables.insert(:users, {id, user})
  def put_current_user(user), do: Tables.insert(:users, {:me, user})

  def put_member(guild_id, %{user: %{id: user_id}} = member) do
    put_user(member.user)
    Tables.insert(:members, {{guild_id, user_id}, %{member | user: nil}})
  end

  def put_member(_guild_id, _member), do: :ok

  def delete_member(guild_id, user_id) do
    for resource <- [:members, :presences, :voice_states],
        do: Tables.delete(resource, {guild_id, user_id})
  end

  def put_role(guild_id, %{id: role_id} = role),
    do: Tables.insert(:roles, {{guild_id, role_id}, role})

  def delete_role(guild_id, role_id), do: Tables.delete(:roles, {guild_id, role_id})

  def put_message(%{id: id, channel_id: channel_id, author: author} = message) do
    if author, do: put_user(author)
    Tables.insert(:messages, {{channel_id, id}, message})
    evict_messages(channel_id)
  end

  def delete_message(channel_id, message_id),
    do: Tables.delete(:messages, {channel_id, message_id})

  # MESSAGE_UPDATE can be partial
  def merge_message(channel_id, data) do
    case Cache.get_message(channel_id, data["id"] || data[:id]) do
      nil ->
        put_message(Lingo.Type.Message.new(data))

      existing ->
        Tables.insert(:messages, {{channel_id, existing.id}, Merge.message(existing, data)})
    end
  end

  def put_presence(guild_id, %{user: %{id: user_id} = user} = presence) do
    case Cache.get_user(user_id) do
      nil -> if is_binary(Map.get(user, :username)), do: put_user(user)
      existing -> put_user(Merge.user(existing, user))
    end

    Tables.insert(:presences, {{guild_id, user_id}, %{presence | user: nil}})
  end

  def put_presence(_guild_id, _presence), do: :ok

  def put_voice_state(guild_id, %{user_id: user_id, channel_id: nil}),
    do: Tables.delete(:voice_states, {guild_id, user_id})

  def put_voice_state(guild_id, %{user_id: user_id} = voice_state),
    do: Tables.insert(:voice_states, {{guild_id, user_id}, voice_state})

  def put_voice_state(_guild_id, _voice_state), do: :ok

  # keeps the newest messages of each channel
  defp evict_messages(channel_id) do
    if table = Tables.table(:messages) do
      max = Tables.max_messages()
      count = :ets.select_count(table, [{{{channel_id, :_}, :_}, [], [true]}])

      if count > max do
        table
        |> :ets.select([{{{channel_id, :"$1"}, :_}, [], [:"$1"]}], count - max)
        |> elem(0)
        |> Enum.each(&:ets.delete(table, {channel_id, &1}))
      end
    end
  end

  defp delete_by_guild(resource, guild_id),
    do: Tables.select_delete(resource, [{{{guild_id, :_}, :_}, [], [true]}])
end
