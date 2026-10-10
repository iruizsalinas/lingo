defmodule Lingo.Cache.Store do
  @moduledoc false

  alias Lingo.Cache
  alias Lingo.Cache.{Merge, Tables}

  def put_all(resources, entries, fun) do
    if Tables.enabled?(resources), do: Enum.each(entries, fun), else: :ok
  end

  def put_guild(guild) do
    if Tables.enabled?(:guilds),
      do: Tables.insert(:guilds, {guild.id, %{guild | channels: [], members: [], roles: []}}),
      else: :ok
  end

  # A Discord deletion invalidates descendants even when parent caching is off.
  def delete_guild(id) do
    Tables.delete(:guilds, id)

    for resource <- [:members, :roles, :presences, :voice_states],
        do: Tables.select_delete(resource, [{{{id, :_}, :_}, [], [true]}])

    # Payloads may lack guild_id; a known channel still identifies their guild.
    if Tables.enabled?(:messages) do
      :channels
      |> Tables.select([{{:"$1", %{guild_id: id}}, [], [:"$1"]}])
      |> Enum.each(&delete_channel/1)
    end

    Tables.select_delete(:channels, [{{:_, %{guild_id: id}}, [], [true]}])
    Tables.select_delete(:messages, [{{:_, %{guild_id: id}}, [], [true]}])
  end

  def put_channel(%{id: id} = channel), do: Tables.insert(:channels, {id, channel})

  def delete_channel(id) do
    Tables.delete(:channels, id)
    Tables.select_delete(:messages, [{{{id, :_}, :_}, [], [true]}])
  end

  def put_user(%{id: id} = user), do: Tables.insert(:users, {id, user})
  def put_current_user(user), do: Tables.put_current_user(user)

  # Retain an embedded user fallback: the independent user cache may be disabled,
  # filtered, expired, or evicted. Reads prefer its latest version when available.
  def put_member(guild_id, %{user: %{id: user_id}} = member) do
    if Tables.wants?(:users, user_id), do: put_user(member.user)

    if Tables.wants?(:members, user_id),
      do: Tables.insert(:members, {{guild_id, user_id}, member}),
      else: :ok
  end

  def put_member(_, _), do: :ok

  def delete_member(guild_id, user_id) do
    for resource <- [:members, :presences, :voice_states],
        do: Tables.delete(resource, {guild_id, user_id})
  end

  def put_role(guild_id, %{id: id} = role), do: Tables.insert(:roles, {{guild_id, id}, role})
  def delete_role(guild_id, id), do: Tables.delete(:roles, {guild_id, id})

  def put_message(%{id: id, channel_id: channel_id, author: author} = message) do
    if author && Tables.wants?(:users, author.id), do: put_user(author)
    Tables.insert(:messages, {{channel_id, id}, message})
  end

  def delete_message(channel_id, id), do: Tables.delete(:messages, {channel_id, id})

  def merge_message(channel_id, data) do
    if Tables.enabled?(:messages) do
      update_message(
        Cache.get_message(channel_id, data["id"]),
        Map.put_new(data, "channel_id", channel_id)
      )
    else
      :ok
    end
  end

  # Dispatch reuses the old value it already read and returns the parsed value
  # even if policy rejects/evicts it. Cache policy never controls event delivery.
  def update_message(old, data) do
    message = if old, do: Merge.message(old, data), else: Lingo.Type.Message.new(data)
    put_message(message)
    message
  end

  def put_presence(guild_id, %{user: %{id: user_id} = user} = presence) do
    if Tables.enabled?([:users, :presences]) do
      existing = Cache.get_user(user_id) || presence_user(guild_id, user_id)
      user = if existing, do: Merge.user(existing, user), else: user
      if Tables.wants?(:users, user_id) and is_binary(user.username), do: put_user(user)
      Tables.insert(:presences, {{guild_id, user_id}, %{presence | user: user}})
    else
      :ok
    end
  end

  def put_presence(_, _), do: :ok

  # GUILD_CREATE presences are absent from the callback payload, so avoid their
  # full parsing when only the user cache needs them.
  def put_raw_presence(guild_id, data) do
    id = get_in(data, ["user", "id"])

    cond do
      Tables.enabled?(:presences) ->
        put_presence(guild_id, Lingo.Type.Presence.new(Map.put(data, "guild_id", guild_id)))

      Tables.wants?(:users, id) ->
        user = Lingo.Type.User.new(data["user"])

        if old = Cache.get_user(id),
          do: put_user(Merge.user(old, user)),
          else: if(is_binary(user.username), do: put_user(user))

      true ->
        :ok
    end
  end

  defp presence_user(guild_id, user_id) do
    case Tables.get(:presences, {guild_id, user_id}) do
      nil -> nil
      presence -> presence.user
    end
  end

  def put_voice_state(guild_id, %{user_id: id, channel_id: nil}),
    do: Tables.delete(:voice_states, {guild_id, id})

  def put_voice_state(guild_id, %{user_id: id} = state),
    do: Tables.insert(:voice_states, {{guild_id, id}, state})

  def put_voice_state(_, _), do: :ok
end
