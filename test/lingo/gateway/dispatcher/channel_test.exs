defmodule Lingo.Gateway.Dispatcher.ChannelTest do
  use ExUnit.Case, async: true

  alias Lingo.Cache
  alias Lingo.Cache.Store
  alias Lingo.Gateway.Dispatcher.Channel, as: Dispatcher
  alias Lingo.Type.Channel

  for policy <- [true, [max_entries: 100, ttl: 60_000, compressed: true]] do
    @policy policy

    test "thread sync replaces only active threads in its scope with policy #{inspect(policy)}" do
      Lingo.TestBot.start(start: [:cache], cache: [channels: @policy])

      Store.put_channel(%Channel{id: "parent", guild_id: "g", type: :guild_text})

      for type <- [:public_thread, :private_thread, :announcement_thread] do
        Store.put_channel(%Channel{
          id: "stale_#{type}",
          guild_id: "g",
          parent_id: "parent",
          type: type,
          thread_metadata: %{"archived" => false}
        })
      end

      put_thread("other_parent", "g", "elsewhere", false)
      put_thread("other_guild", "else", "parent", false)
      put_thread("archived", "g", "parent", true)
      put_thread("retained", "g", "parent", false)

      event =
        Dispatcher.parse(:thread_list_sync, %{
          "guild_id" => "g",
          "channel_ids" => ["parent"],
          "members" => [],
          "threads" => [
            %{
              "id" => "retained",
              "parent_id" => "parent",
              "type" => 11,
              "name" => "updated",
              "thread_metadata" => %{"archived" => false}
            }
          ]
        })

      assert [%Channel{id: "retained", guild_id: "g"}] = event.threads
      assert Cache.Channel.get("retained").name == "updated"

      for type <- [:public_thread, :private_thread, :announcement_thread],
          do: assert(Cache.Channel.get("stale_#{type}") == nil)

      for id <- ["parent", "archived", "other_parent", "other_guild"],
          do: assert(Cache.Channel.get(id))

      # An explicitly empty scope does not mean the whole guild.
      Dispatcher.parse(:thread_list_sync, %{
        "guild_id" => "g",
        "channel_ids" => [],
        "threads" => []
      })

      assert Cache.Channel.get("retained")

      # Empty thread lists still clear the named channels.
      Dispatcher.parse(:thread_list_sync, %{
        "guild_id" => "g",
        "channel_ids" => ["parent"],
        "threads" => []
      })

      assert Cache.Channel.get("retained") == nil
      assert Cache.Channel.get("other_parent")

      # Omitting channel_ids syncs every parent in this guild.
      Dispatcher.parse(:thread_list_sync, %{"guild_id" => "g", "threads" => []})
      assert Cache.Channel.get("other_parent") == nil
      for id <- ["parent", "archived", "other_guild"], do: assert(Cache.Channel.get(id))
    end
  end

  defp put_thread(id, guild, parent, archived) do
    Store.put_channel(%Channel{
      id: id,
      guild_id: guild,
      parent_id: parent,
      type: :public_thread,
      thread_metadata: %{"archived" => archived}
    })
  end
end
