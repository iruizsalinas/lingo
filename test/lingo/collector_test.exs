defmodule Lingo.CollectorTest do
  use ExUnit.Case

  alias Lingo.Collector

  setup do
    start_supervised!({Registry, keys: :duplicate, name: Lingo.Collector.Registry})
    :ok
  end

  describe "await_component" do
    test "returns {:ok, interaction} when a matching event arrives" do
      task =
        Task.async(fn ->
          Collector.await_component("msg123", timeout: 5_000)
        end)

      # small delay for the registration to happen
      Process.sleep(20)

      # simulate the dispatcher calling try_match
      interaction = %{
        type: :message_component,
        message: %{id: "msg123"},
        data: %{"custom_id" => "confirm"}
      }

      result = Collector.try_match(:interaction_create, interaction)
      assert result == :collected

      assert {:ok, ^interaction} = Task.await(task, 5_000)
    end

    test "returns :timeout when no event arrives" do
      result = Collector.await_component("msg_never", timeout: 100)
      assert result == :timeout
    end

    test "respects filter function" do
      task =
        Task.async(fn ->
          Collector.await_component("msg456",
            timeout: 2_000,
            filter: fn i -> i.data["custom_id"] == "yes" end
          )
        end)

      Process.sleep(20)

      # send a non-matching event
      no_match = %{
        type: :message_component,
        message: %{id: "msg456"},
        data: %{"custom_id" => "no"}
      }

      Collector.try_match(:interaction_create, no_match)

      # send a matching event
      yes_match = %{
        type: :message_component,
        message: %{id: "msg456"},
        data: %{"custom_id" => "yes"}
      }

      assert :collected = Collector.try_match(:interaction_create, yes_match)
      assert {:ok, ^yes_match} = Task.await(task, 5_000)
    end

    test "consumed event returns :collected, suppressing normal dispatch" do
      task =
        Task.async(fn ->
          Collector.await_component("msg789", timeout: 2_000)
        end)

      Process.sleep(20)

      interaction = %{type: :message_component, message: %{id: "msg789"}, data: %{}}
      assert Collector.try_match(:interaction_create, interaction) == :collected
      Task.await(task, 5_000)
    end

    test "non-collectable events return :miss immediately" do
      assert Collector.try_match(:message_create, %{id: "123"}) == :miss
      assert Collector.try_match(:guild_update, %{id: "456"}) == :miss
      assert Collector.try_match(:presence_update, %{}) == :miss
    end
  end

  describe "await_reaction" do
    test "returns {:ok, reaction} when a matching event arrives" do
      task =
        Task.async(fn ->
          Collector.await_reaction("ch1", "msg_react", timeout: 5_000)
        end)

      Process.sleep(20)

      reaction = %{message_id: "msg_react", channel_id: "ch1", emoji: %{name: "👍"}}
      Collector.try_match(:message_reaction_add, reaction)

      assert {:ok, ^reaction} = Task.await(task, 5_000)
    end

    test "filters by channel_id" do
      task =
        Task.async(fn ->
          Collector.await_reaction("ch_correct", "msg_react2", timeout: 500)
        end)

      Process.sleep(20)

      # wrong channel
      wrong = %{message_id: "msg_react2", channel_id: "ch_wrong", emoji: %{name: "👍"}}
      Collector.try_match(:message_reaction_add, wrong)

      assert :timeout = Task.await(task, 5_000)
    end

    test "returns :timeout when no reaction arrives" do
      result = Collector.await_reaction("ch1", "msg_nope", timeout: 100)
      assert result == :timeout
    end
  end

  describe "collect_reactions" do
    test "collects multiple reactions over the timeout period" do
      task =
        Task.async(fn ->
          Collector.collect_reactions("ch1", "msg_poll", timeout: 500)
        end)

      Process.sleep(20)

      r1 = %{message_id: "msg_poll", channel_id: "ch1", emoji: %{name: "👍"}, user_id: "u1"}
      r2 = %{message_id: "msg_poll", channel_id: "ch1", emoji: %{name: "👎"}, user_id: "u2"}
      r3 = %{message_id: "msg_poll", channel_id: "ch1", emoji: %{name: "👍"}, user_id: "u3"}

      Collector.try_match(:message_reaction_add, r1)
      Process.sleep(50)
      Collector.try_match(:message_reaction_add, r2)
      Process.sleep(50)
      Collector.try_match(:message_reaction_add, r3)

      {:ok, reactions} = Task.await(task, 5_000)
      assert length(reactions) == 3
    end

    test "returns empty list when no reactions arrive" do
      {:ok, reactions} = Collector.collect_reactions("ch1", "msg_empty", timeout: 100)
      assert reactions == []
    end

    test "respects filter function" do
      task =
        Task.async(fn ->
          Collector.collect_reactions("ch1", "msg_filter",
            timeout: 300,
            filter: fn r -> r.emoji.name == "👍" end
          )
        end)

      Process.sleep(20)

      yes = %{message_id: "msg_filter", channel_id: "ch1", emoji: %{name: "👍"}, user_id: "u1"}
      no = %{message_id: "msg_filter", channel_id: "ch1", emoji: %{name: "👎"}, user_id: "u2"}

      Collector.try_match(:message_reaction_add, yes)
      Collector.try_match(:message_reaction_add, no)

      {:ok, reactions} = Task.await(task, 5_000)
      assert length(reactions) == 1
      assert hd(reactions).emoji.name == "👍"
    end
  end

  describe "cleanup" do
    test "registry is cleaned up when awaiting process dies" do
      {pid, ref} =
        spawn_monitor(fn ->
          Collector.await_component("msg_cleanup", timeout: 60_000)
        end)

      Process.sleep(20)

      # verify registration exists
      assert Registry.lookup(Lingo.Collector.Registry, {:component, "msg_cleanup"}) != []

      # kill the process
      Process.exit(pid, :kill)
      receive do: ({:DOWN, ^ref, _, _, _} -> :ok)

      Process.sleep(20)

      # registry should be clean
      assert Registry.lookup(Lingo.Collector.Registry, {:component, "msg_cleanup"}) == []
    end

    test "registry is cleaned up after timeout" do
      Collector.await_component("msg_timeout_cleanup", timeout: 50)
      Process.sleep(20)

      assert Registry.lookup(Lingo.Collector.Registry, {:component, "msg_timeout_cleanup"}) == []
    end
  end

  describe "multiple collectors" do
    test "two collectors on different messages both work" do
      t1 =
        Task.async(fn ->
          Collector.await_component("msg_a", timeout: 2_000)
        end)

      t2 =
        Task.async(fn ->
          Collector.await_component("msg_b", timeout: 2_000)
        end)

      Process.sleep(20)

      ia = %{type: :message_component, message: %{id: "msg_a"}, data: %{}}
      ib = %{type: :message_component, message: %{id: "msg_b"}, data: %{}}

      Collector.try_match(:interaction_create, ia)
      Collector.try_match(:interaction_create, ib)

      assert {:ok, ^ia} = Task.await(t1, 5_000)
      assert {:ok, ^ib} = Task.await(t2, 5_000)
    end
  end
end
