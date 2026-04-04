defmodule Lingo.Integration.MemberTest do
  @moduledoc false
  use Lingo.IntegrationCase

  @moduletag timeout: 120_000

  setup do
    guild_id = System.get_env("GUILD_ID")
    if is_nil(guild_id) or guild_id == "", do: raise("GUILD_ID not set")

    {:ok, me} = Lingo.Api.User.get_current()

    {:ok, role} =
      Lingo.Api.Role.create(guild_id, %{name: "lingo-member-test-#{:rand.uniform(99999)}"})

    on_exit(fn ->
      try do
        Lingo.Api.Member.modify_current(guild_id, %{nick: nil})
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end

      Lingo.Api.Role.delete(guild_id, role.id)
    end)

    %{guild_id: guild_id, bot_id: me.id, bot_username: me.username, role_id: role.id}
  end

  describe "get/2" do
    test "returns the bot's own member", %{guild_id: guild_id, bot_id: bot_id} do
      assert {:ok, member} = Lingo.Api.Member.get(guild_id, bot_id)
      assert member.user.id == bot_id
      assert is_list(member.roles)
    end
  end

  describe "list/2" do
    test "returns a list of members with limit", %{guild_id: guild_id} do
      assert {:ok, members} = Lingo.Api.Member.list(guild_id, limit: 5)
      assert is_list(members)
      assert length(members) >= 1
      assert length(members) <= 5
    end

    test "returns exactly 1 member when limit is 1", %{guild_id: guild_id} do
      assert {:ok, members} = Lingo.Api.Member.list(guild_id, limit: 1)
      assert length(members) == 1
    end
  end

  describe "search/3" do
    test "finds the bot by username fragment", %{guild_id: guild_id, bot_username: username} do
      query = String.slice(username, 0, 3)
      assert {:ok, members} = Lingo.Api.Member.search(guild_id, query)
      assert is_list(members)

      ids = Enum.map(members, & &1.user.id)
      assert Enum.any?(ids, fn id -> id == Enum.at(members, 0).user.id end)
    end
  end

  describe "modify_current/3" do
    test "sets the bot nickname", %{guild_id: guild_id} do
      assert {:ok, member} = Lingo.Api.Member.modify_current(guild_id, %{nick: "lingo-test"})
      assert member.nick == "lingo-test"
    end

    test "resets the bot nickname", %{guild_id: guild_id} do
      {:ok, _} = Lingo.Api.Member.modify_current(guild_id, %{nick: "lingo-test"})
      assert {:ok, member} = Lingo.Api.Member.modify_current(guild_id, %{nick: nil})
      assert is_nil(member.nick)
    end
  end

  describe "add_role/4 and remove_role/4" do
    test "adds a role to the bot", %{guild_id: guild_id, bot_id: bot_id, role_id: role_id} do
      assert :ok = Lingo.Api.Member.add_role(guild_id, bot_id, role_id)

      {:ok, member} = Lingo.Api.Member.get(guild_id, bot_id)
      assert role_id in member.roles
    end

    test "removes a role from the bot", %{guild_id: guild_id, bot_id: bot_id, role_id: role_id} do
      :ok = Lingo.Api.Member.add_role(guild_id, bot_id, role_id)
      assert :ok = Lingo.Api.Member.remove_role(guild_id, bot_id, role_id)

      {:ok, member} = Lingo.Api.Member.get(guild_id, bot_id)
      refute role_id in member.roles
    end
  end
end
