defmodule Lingo.Helper.HierarchyTest do
  use ExUnit.Case, async: true

  alias Lingo.Cache.Store
  alias Lingo.Helper.{Member, Role}
  alias Lingo.Type

  @guild "800000000000000000"
  @higher "900000000000000000"
  @lower "1000000000000000000"

  setup do
    Lingo.TestBot.start(
      start: [:cache],
      cache: [guilds: true, roles: true, users: true, members: true]
    )

    Store.put_guild(%Type.Guild{id: @guild, owner_id: "owner"})
    Store.put_role(@guild, %Type.Role{id: @guild, position: 0, permissions: "0"})

    Store.put_role(@guild, %Type.Role{id: @higher, position: 5, permissions: "8", color: 0xFF0000})

    Store.put_role(@guild, %Type.Role{id: @lower, position: 5, permissions: "8", color: 0x0000FF})
    Store.put_current_user(%Type.User{id: "bot"})
    put_member("bot", [@higher])
    put_member("target", [@lower])
    :ok
  end

  test "equal positions rank the lower numeric snowflake higher" do
    peer = "950000000000000000"
    Store.put_role(@guild, %Type.Role{id: peer, position: 5})
    assert Role.compare(@guild, @higher, peer) == :gt
    assert Role.compare(@guild, @higher, @lower) == :gt
    assert Role.compare(@guild, @lower, @higher) == :lt
    assert Role.compare(@guild, @higher, @higher) == :eq
  end

  test "the bot can edit and moderate below a tied position" do
    assert Role.editable?(@guild, @lower)
    assert Member.manageable?(@guild, "target")
    assert Member.kickable?(@guild, "target")
    assert Member.bannable?(@guild, "target")

    put_member("bot", [@lower])
    put_member("target", [@higher])
    refute Role.editable?(@guild, @higher)
    refute Member.manageable?(@guild, "target")
  end

  test "a member's highest role and display color use the same tie breaker" do
    put_member("bot", [@lower, @higher])
    assert Member.manageable?(@guild, "target")
    assert Member.display_color(@guild, "bot") == 0xFF0000
  end

  test "everyone stays below another role at position zero" do
    Store.put_role(@guild, %Type.Role{id: @higher, position: 0, permissions: "8"})
    assert Role.compare(@guild, @guild, @higher) == :lt
    assert Role.compare(@guild, @higher, @guild) == :gt
    put_member("target", [])
    assert Member.manageable?(@guild, "target")
  end

  defp put_member(id, roles) do
    Store.put_member(@guild, %Type.Member{user: %Type.User{id: id}, roles: roles})
  end
end
