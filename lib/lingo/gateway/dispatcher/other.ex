defmodule Lingo.Gateway.Dispatcher.Other do
  @moduledoc false

  # The other events that touch the cache: voice states, presences and the
  # bot's own user. Each parse/2 updates the cache and returns the event's
  # payload.

  alias Lingo.Cache
  alias Lingo.Cache.Store
  alias Lingo.Event.Ready
  alias Lingo.Type.{Presence, User, VoiceState}

  def parse(:voice_state_update, data) do
    vs = VoiceState.new(data)
    old = Cache.VoiceState.get(data["guild_id"], vs.user_id)
    Store.put_voice_state(data["guild_id"], vs)
    %{old: old, new: vs}
  end

  def parse(:presence_update, data) do
    p = Presence.new(data)
    user_id = get_in(data, ["user", "id"])
    old = Cache.Presence.get(data["guild_id"], user_id)
    Store.put_presence(data["guild_id"], p)
    new = Cache.Presence.get(data["guild_id"], user_id) || p
    %{old: old, new: new}
  end

  # USER_UPDATE is only sent for the current user

  def parse(:user_update, data) do
    u = User.new(data)
    old = Cache.User.get_current() || Cache.User.get(u.id)
    Store.put_user(u)
    Store.put_current_user(u)
    %{old: old, new: u}
  end

  def parse(:ready, data) do
    ready = Ready.new(data)
    if ready.user, do: Store.put_current_user(ready.user)
    ready
  end

  def parse(_event, _data), do: :skip
end
