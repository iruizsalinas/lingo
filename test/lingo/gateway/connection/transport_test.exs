defmodule Lingo.Gateway.Connection.TransportTest do
  use ExUnit.Case, async: true

  alias Lingo.Gateway.{Connection, WebSocket}
  alias Lingo.Test.WebSocketServer, as: Server

  defmodule EventBot do
    use Lingo.Bot

    @impl true
    def handle_event(:rate_limited, data),
      do: send(Lingo.Instance.get(:test_pid), {:rate_limited, data})
  end

  setup do
    bot = Lingo.TestBot.start(bot: EventBot, test_pid: self(), start: [:cache, :collector])

    {ws, server} = Server.connect()
    :ok = WebSocket.activate(ws)

    state = %Connection{bot: bot, ws: ws, shard_id: 0, shard_count: 1, token: "token", intents: 1}
    %{state: state, server: server}
  end

  # sends bytes from the server and hands the resulting socket message to the connection
  defp deliver(state, server, iodata) do
    :ok = :gen_tcp.send(server, iodata)
    assert_receive {:tcp, _socket, _data} = message
    Connection.handle_info(message, state)
  end

  defp deliver_json(state, server, payload),
    do: deliver(state, server, frame(:text, JSON.encode!(payload)))

  defp frame(opcode, payload, opts \\ []),
    do: Lingo.Gateway.WebSocket.Frame.encode(opcode, payload, opts)

  defp sent_payload(server, timeout \\ 1_000) do
    case Server.recv_frame(server, timeout) do
      {:text, true, json} -> JSON.decode!(json)
      {:error, :timeout} -> nil
    end
  end

  defp stop_heartbeat(%{heartbeat_pid: pid}) when is_pid(pid) do
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
  end

  defp stop_heartbeat(_state), do: :ok

  describe "sending" do
    test "a missed heartbeat ACK closes resumably and reconnects", %{
      state: state,
      server: server
    } do
      state = %{state | state: :identifying, seq: 5}

      assert {:noreply, new_state} = Connection.handle_info(:heartbeat_timeout, state)

      assert Server.recv_frame(server) == {:close, true, <<4000::16>>}
      assert new_state.state == :disconnected
      assert new_state.ws == nil
      assert new_state.connect_timer
      # the session is kept so the next connection resumes
      assert new_state.seq == 5
    end

    test "payloads are queued until the session is ready", %{state: state, server: server} do
      state = %{state | state: :identifying}

      {:noreply, state} = Connection.handle_cast({:send, %{"op" => 3, "d" => %{}}}, state)
      assert sent_payload(server, 100) == nil

      ready = %{
        "op" => 0,
        "t" => "READY",
        "s" => 1,
        "d" => %{"session_id" => "s1", "resume_gateway_url" => "wss://resume.example"}
      }

      {:noreply, state} = deliver_json(state, server, ready)

      assert %{"op" => 3} = sent_payload(server)
      assert state.state == :connected
      assert state.resume_gateway_url == "wss://resume.example"
      assert :queue.is_empty(state.outbox.queue)
    end

    test "sends over the gateway limit wait for the next window", %{state: state, server: server} do
      state = %{
        state
        | state: :connected,
          outbox: %Lingo.Gateway.Connection.Outbox{
            count: 115,
            window_start: System.monotonic_time(:millisecond)
          }
      }

      {:noreply, state} = Connection.handle_cast({:send, %{"op" => 3, "d" => %{}}}, state)

      assert sent_payload(server, 100) == nil
      assert state.send_timer
      assert :queue.len(state.outbox.queue) == 1
      Process.cancel_timer(state.send_timer)
    end

    test "HELLO schedules identify and heartbeats use the latest seq", %{
      state: state,
      server: server
    } do
      state = %{state | state: :awaiting_hello}

      {:noreply, state} =
        deliver_json(state, server, %{"op" => 10, "d" => %{"heartbeat_interval" => 60_000}})

      stop_heartbeat(state)
      assert state.state == :waiting_to_identify
      assert state.identify_timer

      {:noreply, state} = Connection.handle_info(:identify, state)
      assert %{"op" => 2, "d" => %{"shard" => [0, 1]}} = sent_payload(server)
      assert state.state == :identifying

      {:noreply, _state} = Connection.handle_info(:send_heartbeat, %{state | seq: 42})
      assert %{"op" => 1, "d" => 42} = sent_payload(server)
    end

    test "HELLO resumes an existing session", %{state: state, server: server} do
      state = %{state | state: :awaiting_hello, session_id: "s1", seq: 7}

      {:noreply, state} =
        deliver_json(state, server, %{"op" => 10, "d" => %{"heartbeat_interval" => 60_000}})

      stop_heartbeat(state)
      assert state.state == :resuming
      assert %{"op" => 6, "d" => %{"session_id" => "s1", "seq" => 7}} = sent_payload(server)
    end
  end
end
