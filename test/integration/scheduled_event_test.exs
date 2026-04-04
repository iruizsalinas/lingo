defmodule Lingo.Integration.ScheduledEventTest do
  @moduledoc false
  use Lingo.IntegrationCase

  setup do
    guild_id = System.get_env("GUILD_ID")
    if is_nil(guild_id) or guild_id == "", do: raise("GUILD_ID not set")
    %{guild_id: guild_id}
  end

  defp event_params do
    %{
      name: "Lingo Test Event #{:rand.uniform(99999)}",
      scheduled_start_time: DateTime.utc_now() |> DateTime.add(86400) |> DateTime.to_iso8601(),
      scheduled_end_time: DateTime.utc_now() |> DateTime.add(90000) |> DateTime.to_iso8601(),
      entity_type: 3,
      privacy_level: 2,
      entity_metadata: %{location: "Test Location"}
    }
  end

  describe "list/1" do
    test "returns a list", %{guild_id: guild_id} do
      assert {:ok, events} = Lingo.Api.ScheduledEvent.list(guild_id)
      assert is_list(events)
    end
  end

  describe "create/2" do
    test "creates an external event and returns it", %{guild_id: guild_id} do
      params = event_params()
      assert {:ok, event} = Lingo.Api.ScheduledEvent.create(guild_id, params)
      assert is_binary(event.id)
      assert event.name == params.name
      assert event.entity_type == :external
      assert event.status == :scheduled

      Lingo.Api.ScheduledEvent.delete(guild_id, event.id)
    end
  end

  describe "get/2" do
    test "retrieves a created event by ID", %{guild_id: guild_id} do
      {:ok, event} = Lingo.Api.ScheduledEvent.create(guild_id, event_params())

      assert {:ok, fetched} = Lingo.Api.ScheduledEvent.get(guild_id, event.id)
      assert fetched.id == event.id
      assert fetched.name == event.name

      Lingo.Api.ScheduledEvent.delete(guild_id, event.id)
    end
  end

  describe "modify/3" do
    test "renames the event", %{guild_id: guild_id} do
      {:ok, event} = Lingo.Api.ScheduledEvent.create(guild_id, event_params())

      assert {:ok, updated} =
               Lingo.Api.ScheduledEvent.modify(guild_id, event.id, %{name: "Renamed"})

      assert updated.id == event.id
      assert updated.name == "Renamed"

      Lingo.Api.ScheduledEvent.delete(guild_id, event.id)
    end
  end

  describe "get_users/2" do
    test "returns a list of users", %{guild_id: guild_id} do
      {:ok, event} = Lingo.Api.ScheduledEvent.create(guild_id, event_params())

      assert {:ok, users} = Lingo.Api.ScheduledEvent.get_users(guild_id, event.id)
      assert is_list(users)

      Lingo.Api.ScheduledEvent.delete(guild_id, event.id)
    end
  end

  describe "delete/2" do
    test "deletes an event", %{guild_id: guild_id} do
      {:ok, event} = Lingo.Api.ScheduledEvent.create(guild_id, event_params())

      assert :ok = Lingo.Api.ScheduledEvent.delete(guild_id, event.id)
      assert {:error, {404, _}} = Lingo.Api.ScheduledEvent.get(guild_id, event.id)
    end
  end
end
