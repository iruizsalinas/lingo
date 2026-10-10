defmodule Lingo.Cache.SelectionTest do
  use ExUnit.Case, async: true
  alias Lingo.Cache
  alias Lingo.Cache.{Store, Tables}
  alias Lingo.Type.{Channel, Guild, Role}

  test "selectors match default-valued fields and project reconstructed values" do
    for compressed <- [true, false], ttl <- [:infinity, 10_000] do
      Lingo.TestBot.start(
        start: [:cache],
        cache: [only: [:roles], roles: [compressed: compressed, ttl: ttl]]
      )

      Store.put_role("g", %Role{id: "r", guild_id: "g"})
      assert Tables.select(:roles, [{{{"g", :_}, %{managed: false}}, [], [true]}]) == [true]
      assert [%Role{managed: false, position: 0}] = Cache.list_roles("g")

      assert [%Role{managed: false}] =
               Tables.select(:roles, [
                 {{{"g", :_}, :"$1"}, [{:"=:=", {:map_get, :position, :"$1"}, 0}], [:"$1"]}
               ])
    end
  end

  test "chunked TTL queries handle multiple batches and don't return expired entries" do
    for compact <- [true, false] do
      Lingo.TestBot.start(
        start: [:cache],
        cache: [
          only: [:guilds],
          guilds: [compact: compact, ttl: 10_000, keep: fn guild, _ -> guild.id == "kept" end]
        ]
      )

      for id <- 1..300, do: Store.put_guild(%Guild{id: "#{id}"})
      Store.put_guild(%Guild{id: "kept"})
      assert length(Cache.list_guilds()) == 301
      assert :ets.info(Tables.table(:guilds), :safe_fixed) == false
      assert Tables.select_delete(:guilds, [{{:_, %{unavailable: false}}, [], [true]}]) == 301
      assert Cache.list_guilds() == []
      assert Cache.stats().guilds.kept == 0
    end
  end

  test "delete match specs preserve false results and first matching clause" do
    for max <- [:infinity, 10] do
      Lingo.TestBot.start(
        start: [:cache],
        cache: [only: [:channels], channels: [max_entries: max]]
      )

      Store.put_channel(%Channel{id: "c"})
      spec = [{{"c", :_}, [], [false]}, {{:_, :_}, [], [true]}]
      assert Tables.select_delete(:channels, spec) == 0
      assert Cache.get_channel("c").id == "c"
      assert Tables.select_delete(:channels, [{{:_, %{guild_id: nil}}, [], [true]}]) == 1
      assert Cache.get_channel("c") == nil
    end
  end

  test "scoped deletion targets only the matching guild across several batches" do
    Lingo.TestBot.start(
      start: [:cache],
      cache: [only: [:roles], roles: [max_entries_per_guild: 1_000, compressed: true]]
    )

    for guild <- ["g", "other"],
        id <- 1..200,
        do: Store.put_role(guild, %Role{id: "#{id}", guild_id: guild})

    Store.delete_guild("g")
    assert Cache.list_roles("g") == []
    assert length(Cache.list_roles("other")) == 200
    assert Cache.stats().roles.entries == 200
    Cache.clear(:roles)
    assert Cache.stats().roles.entries == 0
  end
end
