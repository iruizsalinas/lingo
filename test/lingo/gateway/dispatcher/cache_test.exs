defmodule Lingo.Gateway.Dispatcher.CacheTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias Lingo.Cache
  alias Lingo.Cache.Store
  alias Lingo.Gateway.Dispatcher
  alias Lingo.Type.{Channel, Guild, Member, Message, Presence, Role, User, VoiceState}

  defmodule EventBot do
    use Lingo.Bot
    @impl true
    def handle_event(event, data), do: send(Lingo.Instance.get(:test_pid), {event, data})
  end

  defp start(cache),
    do:
      Lingo.TestBot.start(
        bot: EventBot,
        test_pid: self(),
        user_id: "me",
        start: [:cache, :collector],
        cache: cache
      )

  defp guild do
    %{
      "id" => "g",
      "name" => "guild",
      "owner_id" => "owner",
      "members" => [%{"user" => %{"id" => "me", "username" => "bot"}, "roles" => ["r"]}],
      "channels" => [%{"id" => "c", "type" => 0}],
      "roles" => [
        %{"id" => "g", "permissions" => "1024", "position" => 0},
        %{"id" => "r", "permissions" => "2048", "position" => 1}
      ]
    }
  end

  test "every resource can be disabled without suppressing typed events" do
    resources = Lingo.Cache.Policy.resources()

    configs = [
      false,
      []
      | Enum.map(resources, fn disabled ->
          Enum.map(resources, &{&1, &1 != disabled})
        end)
    ]

    for config <- configs do
      start(config)
      Dispatcher.dispatch(:guild_create, guild())
      assert_receive {:guild_create, %Guild{members: [%Member{}], roles: [%Role{}, %Role{}]}}
      Dispatcher.dispatch(:guild_update, %{"id" => "g", "name" => "renamed"})
      assert_receive {:guild_update, %{new: %Guild{name: "renamed"}}}
      Dispatcher.dispatch(:channel_create, %{"id" => "c", "guild_id" => "g", "type" => 0})
      assert_receive {:channel_create, %Channel{}}
      Dispatcher.dispatch(:guild_member_add, %{"guild_id" => "g", "user" => %{"id" => "u"}})
      assert_receive {:guild_member_add, %Member{}}
      Dispatcher.dispatch(:guild_role_create, %{"guild_id" => "g", "role" => %{"id" => "r"}})
      assert_receive {:guild_role_create, %Role{}}

      Dispatcher.dispatch(:message_create, %{
        "id" => "m",
        "channel_id" => "c",
        "content" => "before"
      })

      assert_receive {:message_create, %Message{content: "before"}}

      Dispatcher.dispatch(:message_update, %{
        "id" => "m",
        "channel_id" => "c",
        "content" => "after"
      })

      assert_receive {:message_update, %{new: %Message{content: "after"}}}

      Dispatcher.dispatch(:presence_update, %{
        "guild_id" => "g",
        "user" => %{"id" => "u"},
        "status" => "idle"
      })

      assert_receive {:presence_update, %{new: %Presence{status: :idle}}}

      Dispatcher.dispatch(:voice_state_update, %{
        "guild_id" => "g",
        "user_id" => "u",
        "channel_id" => "c"
      })

      assert_receive {:voice_state_update, %{new: %VoiceState{}}}
      Dispatcher.dispatch(:guild_delete, %{"id" => "g"})
      assert_receive {:guild_delete, %{new: %{id: "g"}}}
    end
  end

  test "disabled cache-only collections are not parsed" do
    start(false)

    payload =
      Map.merge(guild(), %{
        "threads" => :invalid,
        "voice_states" => :invalid,
        "presences" => :invalid
      })

    Dispatcher.dispatch(:guild_create, payload)
    assert_receive {:guild_create, %Guild{}}
    assert Cache.Guild.get("g") == nil
  end

  test "user-only self caching skips full cache-only presence parsing" do
    start(only: [:users], users: :self)

    payload =
      Map.put(guild(), "presences", [
        %{"user" => %{"id" => "other"}, "activities" => :invalid},
        %{"user" => %{"id" => "me", "username" => "updated"}, "activities" => :invalid}
      ])

    Dispatcher.dispatch(:guild_create, payload)
    assert_receive {:guild_create, %Guild{}}
    assert Cache.User.get("me").username == "updated"
    assert Cache.User.get("other") == nil
  end

  test "rejected updates still dispatch parsed values with an empty cache" do
    start(only: [:messages], messages: [filter: fn _, _ -> false end])
    Dispatcher.dispatch(:message_update, %{"id" => "m", "channel_id" => "c", "content" => "new"})
    assert_receive {:message_update, %{old: nil, new: %Message{content: "new"}}}
    assert Cache.Message.get("c", "m") == nil
  end

  test "a failing custom predicate cannot suppress typed callbacks" do
    start(only: [:guilds], guilds: [filter: fn _, _ -> raise "oops" end])

    assert capture_log(fn ->
             Dispatcher.dispatch(:guild_create, guild())
             assert_receive {:guild_create, %Guild{}}
           end) =~ "Cache policy failed"

    assert Cache.Guild.get("g") == nil
  end

  test "explicit permission caches retain self without caching other members" do
    start(guilds: true, channels: true, roles: true, users: :self, members: :self)
    Dispatcher.dispatch(:shard_ready, %{"user" => %{"id" => "me", "username" => "bot"}})
    assert_receive {:shard_ready, _}
    Dispatcher.dispatch(:guild_create, guild())
    assert_receive {:guild_create, %Guild{}}
    assert Lingo.Helper.Channel.viewable?("c")
    assert {:ok, 3072} = Lingo.Helper.Channel.fetch_permissions("c", "me")
    Store.put_member("g", %Member{user: %User{id: "other"}, roles: ["r"]})
    assert Cache.Member.get("g", "other") == nil

    assert {:error, {:missing_cache, :member}} =
             Lingo.Helper.Member.fetch_permissions("g", "other")

    Store.delete_role("g", "r")

    assert {:error, {:missing_cache, :role}} =
             Lingo.Helper.Channel.fetch_permissions("c", "me")

    assert Lingo.Helper.Channel.permissions("c", "me") == 0
  end
end
