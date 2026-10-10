defmodule Lingo.Gateway.Dispatcher.Channel do
  @moduledoc false

  # Channel and thread events. Each parse/2 updates the cache and returns the
  # event's payload.

  alias Lingo.Cache
  alias Lingo.Cache.Store
  alias Lingo.Event.{ThreadDelete, ThreadListSync}
  alias Lingo.Type.Channel

  def parse(event, data) when event in [:channel_create, :thread_create] do
    ch = Channel.new(data)
    Store.put_channel(ch)
    ch
  end

  def parse(event, data) when event in [:channel_update, :thread_update] do
    ch = Channel.new(data)
    old = Cache.Channel.get(ch.id)
    Store.put_channel(ch)
    %{old: old, new: ch}
  end

  # Discord sends the whole channel, but only the ids of a thread
  def parse(:channel_delete, data) do
    ch = Channel.new(data)
    Store.delete_channel(ch.id)
    ch
  end

  def parse(:thread_delete, data) do
    event = ThreadDelete.new(data)
    old = Cache.Channel.get(event.id)
    Store.delete_channel(event.id)
    %{event | old: old}
  end

  def parse(:thread_list_sync, data) do
    sync = ThreadListSync.new(data)
    Store.put_all(:channels, sync.threads, &Store.put_channel/1)
    sync
  end

  def parse(_event, _data), do: :skip
end
