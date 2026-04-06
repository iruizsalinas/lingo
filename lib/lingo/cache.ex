defmodule Lingo.Cache do
  @moduledoc false

  use GenServer

  @all_resources [
    :guilds,
    :channels,
    :users,
    :members,
    :presences,
    :roles,
    :voice_states,
    :messages
  ]

  @resource_tables %{
    guilds: :lingo_guilds,
    channels: :lingo_channels,
    users: :lingo_users,
    members: :lingo_members,
    presences: :lingo_presences,
    roles: :lingo_roles,
    voice_states: :lingo_voice_states,
    messages: :lingo_messages
  }

  @default_opts [
    max_messages_per_channel: 200,
    enabled: @all_resources
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(false), do: init(enabled: [])

  def init(opts) do
    config = Keyword.merge(@default_opts, opts)
    enabled = config[:enabled] |> List.wrap() |> Map.new(&{&1, true})

    :persistent_term.put(:lingo_cache_enabled, enabled)
    :persistent_term.put(:lingo_max_messages, config[:max_messages_per_channel])

    for {resource, table} <- @resource_tables, Map.has_key?(enabled, resource) do
      if resource == :messages do
        :ets.new(table, [:named_table, :public, :ordered_set, {:read_concurrency, true}])
      else
        :ets.new(table, [:named_table, :public, :set, {:read_concurrency, true}])
      end
    end

    {:ok, %{}}
  end

  # Guilds

  def get_guild(id), do: ets_get(:lingo_guilds, id)
  def put_guild(%{id: id} = guild), do: safe_insert(:lingo_guilds, {id, guild})

  def delete_guild(id) do
    safe_delete(:lingo_guilds, id)
    delete_by_guild(:lingo_members, id)
    delete_by_guild(:lingo_roles, id)
    delete_by_guild(:lingo_presences, id)
    delete_by_guild(:lingo_voice_states, id)

    # single scan: collect channel IDs during deletion, then clean up their messages
    channel_ids = pop_guild_channels(id)
    Enum.each(channel_ids, &delete_channel_messages/1)
  end

  def list_guilds do
    if table_exists?(:lingo_guilds) do
      :ets.tab2list(:lingo_guilds) |> Enum.map(&elem(&1, 1))
    else
      []
    end
  end

  # Channels

  def get_channel(id), do: ets_get(:lingo_channels, id)
  def put_channel(%{id: id} = channel), do: safe_insert(:lingo_channels, {id, channel})

  def delete_channel(id) do
    safe_delete(:lingo_channels, id)
    delete_channel_messages(id)
  end

  # Users

  def get_user(id), do: ets_get(:lingo_users, id)
  def put_user(%{id: id} = user), do: safe_insert(:lingo_users, {id, user})

  def get_current_user, do: ets_get(:lingo_users, :me)
  def put_current_user(user), do: safe_insert(:lingo_users, {:me, user})

  # Members - keyed {guild_id, user_id}
  # user is stored separately in :lingo_users to avoid duplication

  def get_member(guild_id, user_id) do
    case ets_get(:lingo_members, {guild_id, user_id}) do
      nil -> nil
      member -> %{member | user: get_user(user_id)}
    end
  end

  def put_member(guild_id, %{user: %{id: user_id}} = member) do
    put_user(member.user)
    safe_insert(:lingo_members, {{guild_id, user_id}, %{member | user: nil}})
  end

  def put_member(_guild_id, _member), do: :ok

  def delete_member(guild_id, user_id) do
    safe_delete(:lingo_members, {guild_id, user_id})
    safe_delete(:lingo_presences, {guild_id, user_id})
    safe_delete(:lingo_voice_states, {guild_id, user_id})
  end

  # Roles - keyed {guild_id, role_id}

  def get_role(guild_id, role_id), do: ets_get(:lingo_roles, {guild_id, role_id})

  def put_role(guild_id, %{id: role_id} = role) do
    safe_insert(:lingo_roles, {{guild_id, role_id}, role})
  end

  def delete_role(guild_id, role_id), do: safe_delete(:lingo_roles, {guild_id, role_id})

  def list_roles(guild_id) do
    if table_exists?(:lingo_roles) do
      :ets.select(:lingo_roles, [{{{guild_id, :_}, :"$1"}, [], [:"$1"]}])
    else
      []
    end
  end

  # Messages - ordered_set keyed {channel_id, message_id}

  def get_message(channel_id, message_id), do: ets_get(:lingo_messages, {channel_id, message_id})

  def put_message(%{id: id, channel_id: channel_id, author: author} = message) do
    if author, do: put_user(author)
    safe_insert(:lingo_messages, {{channel_id, id}, message})
    evict_channel_messages(channel_id)
  end

  def delete_message(channel_id, message_id) do
    safe_delete(:lingo_messages, {channel_id, message_id})
  end

  def merge_message(channel_id, data) do
    msg_id = data["id"] || data[:id]

    case get_message(channel_id, msg_id) do
      nil ->
        put_message(Lingo.Type.Message.new(data))

      existing ->
        merged = merge_into_struct(existing, data)
        safe_insert(:lingo_messages, {{channel_id, merged.id}, merged})
    end
  end

  # Presences - keyed {guild_id, user_id}
  # user reference stored separately, not duplicated here

  def get_presence(guild_id, user_id), do: ets_get(:lingo_presences, {guild_id, user_id})

  def put_presence(guild_id, %{user: %{id: user_id}} = presence) do
    safe_insert(:lingo_presences, {{guild_id, user_id}, %{presence | user: nil}})
  end

  def put_presence(_guild_id, _presence), do: :ok

  # Voice states - keyed {guild_id, user_id}

  def get_voice_state(guild_id, user_id),
    do: ets_get(:lingo_voice_states, {guild_id, user_id})

  def put_voice_state(guild_id, %{user_id: user_id} = vs) do
    if vs.channel_id do
      safe_insert(:lingo_voice_states, {{guild_id, user_id}, vs})
    else
      safe_delete(:lingo_voice_states, {guild_id, user_id})
    end
  end

  def put_voice_state(_guild_id, _vs), do: :ok

  # Helpers

  defp ets_get(table, key) do
    if table_exists?(table) do
      case :ets.lookup(table, key) do
        [{^key, value}] -> value
        [] -> nil
      end
    else
      nil
    end
  end

  defp safe_insert(table, entry) do
    if table_exists?(table), do: :ets.insert(table, entry), else: :ok
  end

  defp safe_delete(table, key) do
    if table_exists?(table), do: :ets.delete(table, key), else: :ok
  end

  defp table_exists?(table) do
    :ets.whereis(table) != :undefined
  end

  defp evict_channel_messages(channel_id) do
    if table_exists?(:lingo_messages) do
      max = :persistent_term.get(:lingo_max_messages, 200)
      count = count_channel_messages(channel_id)

      if count > max do
        to_delete = count - max

        :lingo_messages
        |> :ets.select(
          [{{{channel_id, :"$1"}, :_}, [], [:"$1"]}],
          to_delete
        )
        |> elem(0)
        |> Enum.each(fn msg_id ->
          :ets.delete(:lingo_messages, {channel_id, msg_id})
        end)
      end
    end
  end

  defp count_channel_messages(channel_id) do
    if table_exists?(:lingo_messages) do
      :ets.select_count(:lingo_messages, [{{{channel_id, :_}, :_}, [], [true]}])
    else
      0
    end
  end

  defp delete_channel_messages(channel_id) do
    if table_exists?(:lingo_messages) do
      :ets.select_delete(:lingo_messages, [{{{channel_id, :_}, :_}, [], [true]}])
    end
  end

  defp pop_guild_channels(guild_id) do
    if table_exists?(:lingo_channels) do
      ids =
        :ets.select(:lingo_channels, [
          {{:"$1", %{guild_id: guild_id}}, [], [:"$1"]}
        ])

      Enum.each(ids, fn id -> :ets.delete(:lingo_channels, id) end)
      ids
    else
      []
    end
  end

  defp delete_by_guild(table, guild_id) do
    if table_exists?(table) do
      :ets.select_delete(table, [{{{guild_id, :_}, :_}, [], [true]}])
    end
  end

  defp merge_into_struct(struct, data) when is_map(data) do
    fields = struct |> Map.from_struct() |> Map.keys()

    Enum.reduce(fields, struct, fn field, acc ->
      str_key = Atom.to_string(field)

      case Map.fetch(data, str_key) do
        {:ok, value} -> Map.put(acc, field, merge_field(Map.get(acc, field), value))
        :error -> acc
      end
    end)
  end

  defp merge_field(%_{} = existing, value) when is_map(value) and not is_struct(value) do
    merge_into_struct(existing, value)
  end

  defp merge_field(_existing, value), do: value
end
