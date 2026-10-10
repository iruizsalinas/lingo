defmodule Lingo.Gateway.Dispatcher.Message do
  @moduledoc false

  # Message and reaction events. Each parse/2 updates the cache and
  # returns what the bot's handle_event/2 receives.

  alias Lingo.Cache
  alias Lingo.Cache.Store

  alias Lingo.Type.{Message, ReactionEvent}

  def parse(:message_create, data) do
    msg = Message.new(data)
    Store.put_message(msg)
    msg
  end

  # message_update can be partial, merge instead of replace

  def parse(:message_update, data) do
    old = Cache.get_message(data["channel_id"], data["id"])
    new = Store.update_message(old, data)
    %{old: old, new: new}
  end

  def parse(:message_delete, data) do
    old = Cache.get_message(data["channel_id"], data["id"])
    Store.delete_message(data["channel_id"], data["id"])

    %{
      old: old,
      new: %{id: data["id"], channel_id: data["channel_id"], guild_id: data["guild_id"]}
    }
  end

  def parse(:message_delete_bulk, data) do
    ids = data["ids"] || []
    Store.put_all(:messages, ids, fn id -> Store.delete_message(data["channel_id"], id) end)
    %{ids: ids, channel_id: data["channel_id"], guild_id: data["guild_id"]}
  end

  def parse(:message_reaction_add, data), do: ReactionEvent.new(data)

  def parse(:message_reaction_remove, data), do: ReactionEvent.new(data)

  def parse(:message_reaction_remove_all, data) do
    %{channel_id: data["channel_id"], message_id: data["message_id"], guild_id: data["guild_id"]}
  end

  def parse(:message_reaction_remove_emoji, data), do: ReactionEvent.new(data)

  def parse(_event, _data), do: :skip
end
