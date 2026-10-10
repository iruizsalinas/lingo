defmodule Lingo.Cache.RoleTest do
  use ExUnit.Case, async: true

  alias Lingo.Cache
  alias Lingo.Cache.Store
  alias Lingo.Type.Role

  setup do
    %{bot: Lingo.TestBot.start(start: [:cache], cache: [roles: true])}
  end

  test "stores and retrieves a role by guild and id" do
    Store.put_role("g1", %Role{id: "r1", name: "Admin", color: 0xFF0000})
    assert %Role{name: "Admin", color: 0xFF0000} = Cache.Role.get("g1", "r1")
  end

  test "lists a guild's roles" do
    Store.put_role("g1", %Role{id: "r1", name: "Admin"})
    Store.put_role("g1", %Role{id: "r2", name: "Mod"})
    Store.put_role("g2", %Role{id: "r3", name: "Other Guild Role"})

    assert Cache.Role.list("g1") |> Enum.map(& &1.name) |> Enum.sort() == ["Admin", "Mod"]
  end

  test "deletes a role" do
    Store.put_role("g1", %Role{id: "r4", name: "Temp"})
    Store.delete_role("g1", "r4")
    assert Cache.Role.get("g1", "r4") == nil
  end
end
