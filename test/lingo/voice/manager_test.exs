defmodule Lingo.Voice.ManagerTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Lingo.Voice.Manager

  setup do
    bot = Lingo.TestBot.start(user_id: "42")
    supervisor = Lingo.Instance.process_name(bot, Lingo.Voice.Supervisor)
    start_supervised!({DynamicSupervisor, name: supervisor, strategy: :one_for_one})
    start_supervised!({Manager, bot: bot})
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

  test "stopping the manager stops connections it can no longer track" do
    Manager.dispatch(:voice_state_update, voice_state("42", "200"))
    Manager.dispatch(:voice_server_update, voice_server("token"))
    pid = connection()
    ref = Process.monitor(pid)

    stop_supervised!(Manager)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
  end

  test "permanent guild removal closes voice and answers pending joins" do
    Manager.dispatch(:voice_state_update, voice_state("42", "200"))
    Manager.dispatch(:voice_server_update, voice_server("token"))
    pid = connection()
    request = pending_join()
    assert connection() == pid

    Manager.dispatch(:guild_delete, %{"id" => "100"})
    assert connection() == nil
    refute Process.alive?(pid)
    assert {:reply, {:error, :disconnected}} = :gen_server.wait_response(request, 1_000)
  end

  test "a temporary guild outage does not discard the voice session" do
    Manager.dispatch(:voice_state_update, voice_state("42", "200"))
    Manager.dispatch(:voice_server_update, voice_server("token"))
    pid = connection()
    Manager.dispatch(:guild_delete, %{"id" => "100", "unavailable" => true})
    assert connection() == pid
    assert Process.alive?(pid)
  end

  test "a null voice server endpoint disconnects until a replacement is allocated" do
    Manager.dispatch(:voice_state_update, voice_state("42", "200"))
    Manager.dispatch(:voice_server_update, voice_server("first"))
    previous = connection()
    manager = Lingo.Instance.process_name(Manager)
    send(manager, {:lingo_voice_ready, previous, 100})
    assert {:ok, ^previous} = Manager.join("100", "200")

    Manager.dispatch(:voice_server_update, %{
      "guild_id" => "100",
      "token" => "first",
      "endpoint" => nil
    })

    assert connection() == nil
    refute Process.alive?(previous)

    request = :gen_server.send_request(manager, {:join, "100", "200", [timeout: 60_000]})
    assert connection() == nil
    assert :timeout = :gen_server.wait_response(request, 0)

    Manager.dispatch(:voice_server_update, voice_server("replacement"))
    replacement = connection()
    assert is_pid(replacement) and replacement != previous
    assert :sys.get_state(replacement).token == "replacement"
    send(manager, {:lingo_voice_ready, replacement, 100})
    assert {:reply, {:ok, ^replacement}} = :gen_server.wait_response(request, 1_000)
  end

  test "concurrent joins to a new channel wait instead of returning the previous connection" do
    Manager.dispatch(:voice_state_update, voice_state("42", "200"))
    Manager.dispatch(:voice_server_update, voice_server("token"))
    previous = connection()
    manager = Lingo.Instance.process_name(Manager)
    send(manager, {:lingo_voice_ready, previous, 100})
    assert {:ok, ^previous} = Manager.join("100", "200")

    first = :gen_server.send_request(manager, {:join, "100", "300", [timeout: 60_000]})
    assert connection() == previous
    second = :gen_server.send_request(manager, {:join, "100", "300", [timeout: 60_000]})
    assert connection() == previous
    assert :timeout = :gen_server.wait_response(first, 0)
    assert :timeout = :gen_server.wait_response(second, 0)

    Manager.leave("100")
    assert {:reply, {:error, :disconnected}} = :gen_server.wait_response(first, 1_000)
    assert {:reply, {:error, :disconnected}} = :gen_server.wait_response(second, 1_000)
  end

  test "a ready notification queued by the old allocation cannot complete a later join" do
    Manager.dispatch(:voice_state_update, voice_state("42", "200"))
    Manager.dispatch(:voice_server_update, voice_server("first"))
    previous = connection()
    manager = Lingo.Instance.process_name(Manager)

    :sys.suspend(manager)

    try do
      Manager.dispatch(:voice_server_update, %{
        "guild_id" => "100",
        "token" => "first",
        "endpoint" => nil
      })

      :sys.replace_state(previous, fn state ->
        Lingo.Voice.Connection.Playback.check_ready(%{state | status: :connected})
      end)
    after
      :sys.resume(manager)
    end

    assert connection() == nil
    request = :gen_server.send_request(manager, {:join, "100", "200", [timeout: 60_000]})
    assert connection() == nil
    assert :timeout = :gen_server.wait_response(request, 0)
    Manager.leave("100")
    assert {:reply, {:error, :disconnected}} = :gen_server.wait_response(request, 1_000)
  end

  test "a connection becoming ready in the old channel cannot complete a pending move" do
    Manager.dispatch(:voice_state_update, voice_state("42", "200"))
    Manager.dispatch(:voice_server_update, voice_server("first"))
    previous = connection()
    manager = Lingo.Instance.process_name(Manager)
    request = :gen_server.send_request(manager, {:join, "100", "300", [timeout: 60_000]})
    assert connection() == previous

    :sys.replace_state(previous, fn state ->
      Lingo.Voice.Connection.Playback.check_ready(%{state | status: :connected})
    end)

    assert connection() == previous
    assert :timeout = :gen_server.wait_response(request, 0)

    Manager.dispatch(:voice_state_update, voice_state("42", "300"))
    replacement = connection()
    assert replacement != previous
    assert :sys.get_state(replacement).channel_id == 300

    :sys.replace_state(replacement, fn state ->
      Lingo.Voice.Connection.Playback.check_ready(%{state | status: :connected})
    end)

    assert {:reply, {:ok, ^replacement}} = :gen_server.wait_response(request, 1_000)
  end

  test "leaving during a pending join answers the caller" do
    request = pending_join()
    assert :ok = Manager.leave("100")
    assert {:reply, {:error, :disconnected}} = :gen_server.wait_response(request, 1_000)
  end

  test "a replacement connection must send its own ready notification" do
    Manager.dispatch(:voice_state_update, voice_state("42", "200"))
    Manager.dispatch(:voice_server_update, voice_server("first"))
    previous = connection()
    manager = Lingo.Instance.process_name(Manager)
    :sys.suspend(manager)

    try do
      Manager.dispatch(:voice_server_update, voice_server("replacement"))

      :sys.replace_state(previous, fn state ->
        Lingo.Voice.Connection.Playback.check_ready(%{state | status: :connected})
      end)
    after
      :sys.resume(manager)
    end

    replacement = connection()
    assert replacement != previous
    request = :gen_server.send_request(manager, {:join, "100", "200", [timeout: 60_000]})
    assert connection() == replacement
    assert :timeout = :gen_server.wait_response(request, 0)
    Lingo.Voice.Connection.subscribe(replacement)

    :sys.replace_state(replacement, fn state ->
      Lingo.Voice.Connection.Playback.check_ready(%{state | status: :connected})
    end)

    assert {:reply, {:ok, ^replacement}} = :gen_server.wait_response(request, 1_000)
    assert_receive {:lingo_voice, 100, :ready}
  end

  test "being disconnected during a pending join answers the caller" do
    request = pending_join()
    Manager.dispatch(:voice_state_update, voice_state("42", nil))
    assert connection() == nil
    assert {:reply, {:error, :disconnected}} = :gen_server.wait_response(request, 1_000)
  end

  defp pending_join do
    :gen_server.send_request(
      Lingo.Instance.process_name(Manager),
      {:join, "100", "200", [timeout: 60_000]}
    )
  end
end
