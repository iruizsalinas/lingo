defmodule Lingo.Gateway.Dispatcher.Channel do
  @moduledoc false

  # Channel and thread events. Each parse/2 updates the cache and returns the
  # event's payload.

  alias Lingo.Cache
  alias Lingo.Cache.Store
  alias Lingo.Cache.Tables
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
    prune_threads(sync)
    Store.put_all(:channels, sync.threads, &Store.put_channel/1)
    sync
  end

  def parse(_event, _data), do: :skip

  defp prune_threads(sync) do
    ids = Map.new(sync.threads, &{&1.id, true})
    parents = Map.new(sync.channel_ids || [], &{&1, true})

    scope =
      if sync.channel_ids == nil,
        do: [],
        else: [{:is_map_key, :"$2", {:const, parents}}]

    # Only active threads are authoritative here; archived threads can have
    # been cached separately through REST and are absent from this event.
    spec =
      for type <- [:public_thread, :private_thread, :announcement_thread] do
        {{:"$1",
          %{
            guild_id: sync.guild_id,
            parent_id: :"$2",
            type: type,
            thread_metadata: %{"archived" => false}
          }}, scope ++ [{:not, {:is_map_key, :"$1", {:const, ids}}}], [true]}
      end

    Tables.select_delete(:channels, spec)
  end
end
