defmodule Lingo.Gateway.Dispatcher.Channel do
  @moduledoc false

  # Channel and thread events. Each parse/2 updates the cache and
  # returns what the bot's handle_event/2 receives.

  alias Lingo.Cache
  alias Lingo.Cache.Store

  alias Lingo.Type.Channel

  def parse(:channel_create, data) do
    ch = Channel.new(data)
    Store.put_channel(ch)
    ch
  end

  def parse(:channel_update, data) do
    ch = Channel.new(data)
    old = Cache.Channel.get(ch.id)
    Store.put_channel(ch)
    %{old: old, new: ch}
  end

  def parse(:channel_delete, data) do
    ch = Channel.new(data)
    old = Cache.Channel.get(data["id"])
    Store.delete_channel(data["id"])
    %{old: old, new: ch}
  end

  def parse(:thread_create, data) do
    ch = Channel.new(data)
    Store.put_channel(ch)
    ch
  end

  def parse(:thread_update, data) do
    ch = Channel.new(data)
    old = Cache.Channel.get(ch.id)
    Store.put_channel(ch)
    %{old: old, new: ch}
  end

  def parse(:thread_delete, data) do
    ch = Channel.new(data)
    old = Cache.Channel.get(data["id"])
    Store.delete_channel(data["id"])
    %{old: old, new: ch}
  end

  def parse(:thread_list_sync, data) do
    threads =
      Enum.map(
        data["threads"] || [],
        &(Map.put(&1, "guild_id", data["guild_id"]) |> Channel.new())
      )

    Store.put_all(:channels, threads, &Store.put_channel/1)

    %{
      guild_id: data["guild_id"],
      channel_ids: data["channel_ids"],
      threads: threads,
      members: data["members"] || []
    }
  end

  def parse(_event, _data), do: :skip
end
