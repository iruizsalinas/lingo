defmodule Lingo.Gateway.ConnectionTest do
  use ExUnit.Case

  alias Lingo.Gateway.Connection

  defmodule EventBot do
    use Lingo.Bot

    handle :rate_limited, data do
      send(:persistent_term.get({:lingo_test, :connection_parent}), {:rate_limited, data})
    end
  end

  setup do
    previous_bot = Lingo.Config.bot_module()

    :persistent_term.put({:lingo_test, :connection_parent}, self())
    Lingo.Config.put(:bot_module, EventBot)

    on_exit(fn ->
      Lingo.Config.put(:bot_module, previous_bot)
      :persistent_term.erase({:lingo_test, :connection_parent})
    end)
  end

  test "maps RATE_LIMITED dispatches to rate_limited events" do
    payload =
      Jason.encode!(%{
        "op" => 0,
        "t" => "RATE_LIMITED",
        "s" => 12,
        "d" => %{
          "opcode" => 8,
          "retry_after" => 60.0,
          "meta" => %{"guild_id" => "guild1", "nonce" => "nonce1"}
        }
      })

    state = %Connection{gun_pid: self(), stream_ref: :stream, seq: 11}

    assert {:noreply, %Connection{seq: 12}} =
             Connection.handle_info({:gun_ws, self(), :stream, {:text, payload}}, state)

    assert_receive {:rate_limited,
                    %{
                      "opcode" => 8,
                      "retry_after" => 60.0,
                      "meta" => %{"guild_id" => "guild1", "nonce" => "nonce1"}
                    }}
  end

  # the test process stands in for the gun connection, so frames sent through
  # :gun.ws_send/3 arrive here as gen_statem casts
  defp sent_frame do
    receive do
      {:"$gen_cast", {:ws_send, _, :stream, {:text, data}}} -> Jason.decode!(data)
    after
      100 -> nil
    end
  end

  defp gateway_message(payload) do
    {:gun_ws, self(), :stream, {:text, Jason.encode!(payload)}}
  end

  test "ignores gun messages from a previous connection" do
    old_pid = spawn(fn -> :ok end)
    state = %Connection{gun_pid: self(), stream_ref: :stream, state: :connected}

    assert {:noreply, ^state} =
             Connection.handle_info({:gun_down, old_pid, :ws, :closed, []}, state)

    assert {:noreply, ^state} =
             Connection.handle_info({:gun_ws, old_pid, :stream, {:close, 4000, ""}}, state)
  end

  test "a missed heartbeat ACK reconnects even before READY" do
    state = %Connection{gun_pid: self(), stream_ref: :stream, state: :identifying, seq: 5}

    assert {:noreply, new_state} = Connection.handle_info(:heartbeat_timeout, state)

    assert_receive {:"$gen_cast", {:ws_send, _, :stream, {:close, 4000, ""}}}
    assert new_state.state == :disconnected
    assert new_state.gun_pid == nil
    assert new_state.connect_timer
    # the session is kept so the next connection resumes
    assert new_state.seq == 5
  end

  test "payloads are queued until the session is ready" do
    state = %Connection{gun_pid: self(), stream_ref: :stream, state: :identifying, shard_id: 0}

    {:noreply, state} = Connection.handle_cast({:send, %{"op" => 3, "d" => %{}}}, state)
    assert sent_frame() == nil

    ready = %{
      "op" => 0,
      "t" => "READY",
      "s" => 1,
      "d" => %{"session_id" => "s1", "resume_gateway_url" => "wss://resume.example"}
    }

    {:noreply, state} = Connection.handle_info(gateway_message(ready), state)

    assert %{"op" => 3} = sent_frame()
    assert state.state == :connected
    assert :queue.is_empty(state.send_queue)
  end

  test "sends over the gateway limit wait for the next window" do
    state = %Connection{
      gun_pid: self(),
      stream_ref: :stream,
      state: :connected,
      send_count: 115,
      send_window_start: System.monotonic_time(:millisecond)
    }

    {:noreply, state} = Connection.handle_cast({:send, %{"op" => 3, "d" => %{}}}, state)

    assert sent_frame() == nil
    assert state.send_timer
    assert :queue.len(state.send_queue) == 1
    Process.cancel_timer(state.send_timer)
  end

  test "HELLO schedules identify without blocking and heartbeats use the latest seq" do
    state = %Connection{
      gun_pid: self(),
      stream_ref: :stream,
      shard_id: 0,
      shard_count: 1,
      token: "token",
      intents: 1,
      state: :awaiting_hello
    }

    {:noreply, state} =
      Connection.handle_info(
        gateway_message(%{"op" => 10, "d" => %{"heartbeat_interval" => 60_000}}),
        state
      )

    on_exit(fn ->
      if Process.alive?(state.heartbeat_pid), do: GenServer.stop(state.heartbeat_pid)
    end)

    assert state.state == :waiting_to_identify
    assert state.identify_timer

    {:noreply, state} = Connection.handle_info(:identify, state)
    assert %{"op" => 2, "d" => %{"shard" => [0, 1]}} = sent_frame()
    assert state.state == :identifying

    {:noreply, _} = Connection.handle_info(:send_heartbeat, %{state | seq: 42})
    assert %{"op" => 1, "d" => 42} = sent_frame()
  end
end

defmodule Lingo.Gateway.ShardManagerTest do
  use ExUnit.Case, async: true

  alias Lingo.Gateway.ShardManager

  test "identify slots are spaced per max_concurrency bucket" do
    state = %ShardManager{max_concurrency: 2}

    {:reply, 0, state} = ShardManager.handle_call({:reserve_identify, 0}, self(), state)
    {:reply, 0, state} = ShardManager.handle_call({:reserve_identify, 1}, self(), state)
    {:reply, wait, _state} = ShardManager.handle_call({:reserve_identify, 2}, self(), state)

    # shard 2 shares bucket 0 with shard 0
    assert wait > 5_000
  end
end
