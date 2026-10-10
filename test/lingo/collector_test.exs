defmodule Lingo.CollectorTest do
  use ExUnit.Case, async: true

  alias Lingo.Collector

  setup do
    %{bot: Lingo.TestBot.start(start: [:collector])}
  end

  defp registry, do: Lingo.Instance.process_name(Lingo.Collector.Registry)

  # awaiters register from their own process; wait until `count` have
  defp wait_for_registrations(count, tries \\ 200) do
    if Registry.count(registry()) != count and tries > 0 do
      Process.sleep(5)
      wait_for_registrations(count, tries - 1)
    end
  end

  describe "await_component" do
    test "returns {:ok, interaction} when a matching event arrives" do
      task =
        Task.async(fn ->
          Collector.await_component("msg123", timeout: 5_000)
        end)

      # small delay for the registration to happen
      wait_for_registrations(1)

      # simulate the dispatcher calling try_match
      interaction = %{
        type: :message_component,
        message: %{id: "msg123"},
        data: %{"custom_id" => "confirm"}
      }

      result = Lingo.Collector.Match.try_match(:interaction_create, interaction)
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

      wait_for_registrations(1)

      # send a non-matching event
      no_match = %{
        type: :message_component,
        message: %{id: "msg456"},
        data: %{"custom_id" => "no"}
      }

      Lingo.Collector.Match.try_match(:interaction_create, no_match)

      # send a matching event
      yes_match = %{
        type: :message_component,
        message: %{id: "msg456"},
        data: %{"custom_id" => "yes"}
      }

      assert :collected = Lingo.Collector.Match.try_match(:interaction_create, yes_match)
      assert {:ok, ^yes_match} = Task.await(task, 5_000)
    end

    test "consumed event returns :collected, suppressing normal dispatch" do
      task =
        Task.async(fn ->
          Collector.await_component("msg789", timeout: 2_000)
        end)

      wait_for_registrations(1)

      interaction = %{type: :message_component, message: %{id: "msg789"}, data: %{}}
      assert Lingo.Collector.Match.try_match(:interaction_create, interaction) == :collected
      Task.await(task, 5_000)
    end

    test "a second matching click is not swallowed once the awaiter is satisfied" do
      task = Task.async(fn -> Collector.await_component("msg_dbl", timeout: 2_000) end)
      wait_for_registrations(1)

      first = %{type: :message_component, message: %{id: "msg_dbl"}, data: %{"n" => 1}}
      second = %{type: :message_component, message: %{id: "msg_dbl"}, data: %{"n" => 2}}

      assert Lingo.Collector.Match.try_match(:interaction_create, first) == :collected
      assert Lingo.Collector.Match.try_match(:interaction_create, second) == :miss
      assert {:ok, ^first} = Task.await(task, 5_000)
    end

    test "non-collectable events return :miss immediately" do
      assert Lingo.Collector.Match.try_match(:message_create, %{id: "123"}) == :miss
      assert Lingo.Collector.Match.try_match(:guild_update, %{id: "456"}) == :miss
      assert Lingo.Collector.Match.try_match(:presence_update, %{}) == :miss
    end
  end

  describe "await_reaction" do
    test "returns {:ok, reaction} when a matching event arrives" do
      task =
        Task.async(fn ->
          Collector.await_reaction("ch1", "msg_react", timeout: 5_000)
        end)

      wait_for_registrations(1)

      reaction = %{message_id: "msg_react", channel_id: "ch1", emoji: %{name: "👍"}}
      Lingo.Collector.Match.try_match(:message_reaction_add, reaction)

      assert {:ok, ^reaction} = Task.await(task, 5_000)
    end

    test "filters by channel_id" do
      task =
        Task.async(fn ->
          Collector.await_reaction("ch_correct", "msg_react2", timeout: 500)
        end)

      wait_for_registrations(1)

      # wrong channel
      wrong = %{message_id: "msg_react2", channel_id: "ch_wrong", emoji: %{name: "👍"}}
      Lingo.Collector.Match.try_match(:message_reaction_add, wrong)

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

      wait_for_registrations(1)

      r1 = %{message_id: "msg_poll", channel_id: "ch1", emoji: %{name: "👍"}, user_id: "u1"}
      r2 = %{message_id: "msg_poll", channel_id: "ch1", emoji: %{name: "👎"}, user_id: "u2"}
      r3 = %{message_id: "msg_poll", channel_id: "ch1", emoji: %{name: "👍"}, user_id: "u3"}

      Lingo.Collector.Match.try_match(:message_reaction_add, r1)
      Process.sleep(50)
      Lingo.Collector.Match.try_match(:message_reaction_add, r2)
      Process.sleep(50)
      Lingo.Collector.Match.try_match(:message_reaction_add, r3)

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

      wait_for_registrations(1)

      yes = %{message_id: "msg_filter", channel_id: "ch1", emoji: %{name: "👍"}, user_id: "u1"}
      no = %{message_id: "msg_filter", channel_id: "ch1", emoji: %{name: "👎"}, user_id: "u2"}

      Lingo.Collector.Match.try_match(:message_reaction_add, yes)
      Lingo.Collector.Match.try_match(:message_reaction_add, no)

      {:ok, reactions} = Task.await(task, 5_000)
      assert length(reactions) == 1
      assert hd(reactions).emoji.name == "👍"
    end
  end

  describe "cleanup" do
    test "registry is cleaned up when awaiting process dies", %{bot: bot} do
      {pid, ref} =
        spawn_monitor(fn ->
          Lingo.put_bot(bot)
          Collector.await_component("msg_cleanup", timeout: 60_000)
        end)

      wait_for_registrations(1)

      # verify registration exists
      assert Registry.lookup(registry(), {:component, "msg_cleanup"}) != []

      # kill the process
      Process.exit(pid, :kill)
      receive do: ({:DOWN, ^ref, _, _, _} -> :ok)

      wait_for_registrations(0)

      # registry should be clean
      assert Registry.lookup(registry(), {:component, "msg_cleanup"}) == []
    end

    test "registry is cleaned up after timeout" do
      Collector.await_component("msg_timeout_cleanup", timeout: 50)
      wait_for_registrations(0)

      assert Registry.lookup(registry(), {:component, "msg_timeout_cleanup"}) == []
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

      wait_for_registrations(2)

      ia = %{type: :message_component, message: %{id: "msg_a"}, data: %{}}
      ib = %{type: :message_component, message: %{id: "msg_b"}, data: %{}}

      Lingo.Collector.Match.try_match(:interaction_create, ia)
      Lingo.Collector.Match.try_match(:interaction_create, ib)

      assert {:ok, ^ia} = Task.await(t1, 5_000)
      assert {:ok, ^ib} = Task.await(t2, 5_000)
    end
  end
end
