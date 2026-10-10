defmodule Lingo.Gateway.Dispatcher.Message do
  @moduledoc false

  # Message events. Each parse/2 updates the cache and returns the event's
  # payload; reactions touch no cache, so the catalog builds them.

  alias Lingo.Cache
  alias Lingo.Cache.Store
  alias Lingo.Event.{MessageDelete, MessageDeleteBulk}
  alias Lingo.Type.Message

  def parse(:message_create, data) do
    msg = Message.new(data)
    Store.put_message(msg)
    msg
  end

  # message_update can be partial, merge instead of replace

  def parse(:message_update, data) do
    old = Cache.Message.get(data["channel_id"], data["id"])
    new = Store.update_message(old, data)
    %{old: old, new: new}
  end

  def parse(:message_delete, data) do
    event = MessageDelete.new(data)
    old = Cache.Message.get(event.channel_id, event.id)
    Store.delete_message(event.channel_id, event.id)
    %{event | old: old}
  end

  def parse(:message_delete_bulk, data) do
    event = MessageDeleteBulk.new(data)
    old = for id <- event.ids, msg = Cache.Message.get(event.channel_id, id), do: msg
    Store.put_all(:messages, event.ids, &Store.delete_message(event.channel_id, &1))
    %{event | old: old}
  end

  def parse(_event, _data), do: :skip
end
