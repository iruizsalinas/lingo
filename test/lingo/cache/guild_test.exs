defmodule Lingo.Cache.GuildTest do
  use ExUnit.Case, async: true

  alias Lingo.Cache
  alias Lingo.Cache.Store
  alias Lingo.Type.Guild

  setup do
    %{bot: Lingo.TestBot.start(start: [:cache], cache: [guilds: true])}
  end

  test "stores and retrieves a guild" do
    Store.put_guild(%Guild{id: "100", name: "Test Server"})
    assert %Guild{id: "100", name: "Test Server"} = Cache.Guild.get("100")
  end

  test "overwrites existing guild on update" do
    Store.put_guild(%Guild{id: "100", name: "Old Name"})
    Store.put_guild(%Guild{id: "100", name: "New Name"})
    assert Cache.Guild.get("100").name == "New Name"
  end

  test "returns nil for missing guild" do
    assert Cache.Guild.get("nonexistent") == nil
  end

  test "deletes a guild" do
    Store.put_guild(%Guild{id: "200", name: "To Delete"})
    Store.delete_guild("200")
    assert Cache.Guild.get("200") == nil
  end

  test "lists all cached guilds" do
    for id <- ["1", "2", "3"], do: Store.put_guild(%Guild{id: id, name: id})
    assert Cache.Guild.list() |> Enum.map(& &1.id) |> Enum.sort() == ["1", "2", "3"]
  end
end
