defmodule Lingo.Cache.StorageTest do
  use ExUnit.Case, async: true
  alias Lingo.Cache
  alias Lingo.Cache.{Storage, Store, Tables}
  alias Lingo.Type.{Attachment, Embed, Guild, Member, Message, Presence, User}

  defp message do
    user = %User{id: "u", username: "alice", bot: true}

    %Message{
      id: "m",
      channel_id: "c",
      guild_id: "g",
      author: user,
      member: %Member{user: user, roles: ["r"], nick: "Alice"},
      mentions: [user],
      mention_members: %{"u" => %Member{user: user}},
      embeds: [%Embed{title: "hello", description: "body"}],
      attachments: [%Attachment{id: "a", filename: "a.txt", size: 100}],
      timestamp: ~U[2026-10-10 12:00:00Z],
      referenced_message: %Message{id: "reply", author: user},
      message_snapshots: [%{"message" => %Message{id: "snapshot"}}],
      components: [%{"type" => 1, "components" => [%{"type" => 2, "label" => "go"}]}]
    }
  end

  test "compact representation round-trips nested structs, opaque maps and exact values" do
    input = message()
    encoded = Storage.encode(input, %{compact: true})
    assert Storage.decode(encoded, %{compact: true}) === input
    assert Storage.encode(input, %{compact: false}) === input
    assert Storage.decode(input, %{compact: false}) === input

    # Equality must be exact: 0.0 is not the default integer 0.
    assert Storage.decode(
             Storage.encode(%Lingo.Type.Role{position: 0.0}, %{compact: true}),
             %{compact: true}
           ).position === 0.0

    assert Storage.decode(Storage.encode(%User{}, %{compact: true}), %{compact: true}) === %User{}

    assert Storage.decode(Storage.encode(%Presence{}, %{compact: true}), %{compact: true}) ===
             %Presence{}
  end

  test "all storage combinations return identical public values and preserve partial updates" do
    for compact <- [true, false], compressed <- [true, false] do
      Lingo.TestBot.start(
        start: [:cache],
        cache: [
          messages: [compact: compact, compressed: compressed],
          users: [compact: compact, compressed: compressed, filter: :all, keep: :none]
        ]
      )

      input = message()
      Store.put_message(input)
      assert Cache.Message.get("c", "m") === input
      assert Cache.User.get("u") === input.author
      assert :ets.info(Tables.table(:messages), :compressed) == compressed

      updated =
        Store.update_message(input, %{
          "id" => "m",
          "channel_id" => "c",
          "content" => "",
          "embeds" => [],
          "attachments" => [],
          "pinned" => false
        })

      assert Cache.Message.get("c", "m") === updated
      assert updated.embeds == []
      assert updated.attachments == []
      assert updated.author === input.author
      assert updated.timestamp === input.timestamp
      assert updated.referenced_message === input.referenced_message
      Store.delete_message("c", "m")
      assert Cache.Message.get("c", "m") == nil
    end
  end

  test "nested user fallback remains complete when its independent cache is off" do
    Lingo.TestBot.start(start: [:cache], cache: [users: false, members: true, presences: true])
    input = message()
    Store.put_member("g", input.member)
    Store.put_presence("g", %Presence{user: input.author, guild_id: "g", status: :idle})
    assert Cache.Member.get("g", "u") === input.member
    assert Cache.Presence.get("g", "u").user === input.author
  end

  test "filter and keep predicates observe complete structs before storage encoding" do
    test_pid = self()

    Lingo.TestBot.start(
      start: [:cache],
      cache: [
        only: [:guilds],
        guilds: [
          max_entries: 0,
          compressed: true,
          keep: fn entry, _ ->
            send(test_pid, entry)
            entry.unavailable == false and entry.roles == []
          end
        ]
      ]
    )

    Store.put_guild(%Guild{id: "g"})
    assert_receive %Guild{unavailable: false, roles: []}
    assert %Guild{id: "g", unavailable: false} = Cache.Guild.get("g")
    assert Cache.stats().guilds.kept == 1
  end

  test "compact storage reduces ETS memory for a representative nested message" do
    policy = %{compact: true, compressed: false}
    compact = Storage.table(policy)
    full = Storage.table(%{policy | compact: false})
    input = message()

    for id <- 1..100 do
      :ets.insert(compact, {id, Storage.encode(input, policy)})
      :ets.insert(full, {id, input})
    end

    assert :ets.info(compact, :memory) < :ets.info(full, :memory)
  end

  test "versioned deletion preserves a concurrent replacement" do
    policy = %{compact: true, compressed: false}
    table = Storage.table(policy)
    selected = message()
    replacement = %{selected | content: "new", author: nil}
    key = {"c", "m"}
    :ets.insert(table, {key, Storage.encode(replacement, policy)})

    assert Storage.delete_version(table, key, selected, policy) == 0
    assert [{^key, stored}] = :ets.lookup(table, key)
    assert Storage.decode(stored, policy) === replacement
    assert Storage.delete_version(table, key, replacement, policy) == 1
    assert :ets.lookup(table, key) == []
  end
end
