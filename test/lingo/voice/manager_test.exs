defmodule Lingo.Voice.ManagerTest do
  use ExUnit.Case

  @moduletag :capture_log

  alias Lingo.Voice.Manager

  setup do
    previous = Lingo.Config.get(:user_id)
    Lingo.Config.put(:user_id, "42")
    on_exit(fn -> Lingo.Config.put(:user_id, previous) end)

    start_supervised!({DynamicSupervisor, name: Lingo.Voice.Supervisor, strategy: :one_for_one})
    start_supervised!(Manager)
    :ok
  end

  defp voice_state(user_id, channel_id),
    do: %{
      "guild_id" => "100",
      "user_id" => user_id,
      "session_id" => "session",
      "channel_id" => channel_id
    }

  defp voice_server(token),
    do: %{"guild_id" => "100", "token" => token, "endpoint" => "127.0.0.1:1"}

  # casts are processed in order, so a call afterwards means they were handled
  defp connection, do: Lingo.Voice.connection("100")

  test "connects once both halves of the voice session are known" do
    join = Task.async(fn -> Lingo.Voice.join("100", "200", timeout: 200) end)

    Manager.dispatch(:voice_state_update, voice_state("7", "200"))
    Manager.dispatch(:voice_state_update, voice_state("42", "200"))
    assert connection() == nil

    Manager.dispatch(:voice_server_update, voice_server("token"))
    pid = connection()
    assert is_pid(pid)

    state = :sys.get_state(pid)

    assert {state.session_id, state.token, state.channel_id, state.user_id} ==
             {"session", "token", 200, 42}

    # the endpoint never answers, so the join gives up
    assert {:error, :timeout} = Task.await(join)
  end

  test "a new voice server replaces the connection, leaving stops it" do
    Manager.dispatch(:voice_state_update, voice_state("42", "200"))
    Manager.dispatch(:voice_server_update, voice_server("first"))
    first = connection()

    Manager.dispatch(:voice_server_update, voice_server("second"))
    second = connection()

    assert second != first
    refute Process.alive?(first)
    assert :sys.get_state(second).token == "second"

    Manager.dispatch(:voice_state_update, voice_state("42", nil))
    assert connection() == nil
    refute Process.alive?(second)
  end

  test "playing without a connection is an error" do
    assert {:error, :not_connected} = Lingo.Voice.play("100", [])
    assert {:error, :not_connected} = Lingo.Voice.listen("100")
  end
end
