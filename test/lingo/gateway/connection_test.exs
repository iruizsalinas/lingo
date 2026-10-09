defmodule Lingo.Gateway.ConnectionTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias Lingo.Gateway.{Connection, WebSocket}
  alias Lingo.Test.WebSocketServer, as: Server

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

    {ws, server} = Server.connect()
    :ok = WebSocket.activate(ws)

    state = %Connection{ws: ws, shard_id: 0, shard_count: 1, token: "token", intents: 1}
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

  describe "connecting" do
    test "connects in a task and waits for HELLO", %{state: state} do
      {listen, url} = Server.listen()
      state = %{state | ws: nil, gateway_url: url}

      {:noreply, state} = Connection.handle_info(:connect, state)
      assert state.state == :connecting
      assert %Task{ref: ref} = state.connect_task

      server = Server.accept(listen)
      assert_receive {^ref, {:ok, _ws}} = result

      {:noreply, state} = Connection.handle_info(result, state)
      assert state.state == :awaiting_hello
      assert state.connect_task == nil
      assert state.hello_timer

      {:noreply, state} =
        deliver_json(state, server, %{"op" => 10, "d" => %{"heartbeat_interval" => 60_000}})

      stop_heartbeat(state)
      assert state.state == :waiting_to_identify
      Process.cancel_timer(state.identify_timer)
    end

    test "schedules a retry when the connection fails", %{state: state} do
      {listen, url} = Server.listen()
      :gen_tcp.close(listen)

      {:noreply, state} = Connection.handle_info(:connect, %{state | ws: nil, gateway_url: url})
      %Task{ref: ref} = state.connect_task
      assert_receive {^ref, {:error, _reason}} = result, 5_000

      {:noreply, state} = Connection.handle_info(result, state)
      assert state.state == :disconnected
      assert state.connect_task == nil
      assert state.connect_timer
    end
  end

  describe "receiving" do
    test "maps RATE_LIMITED dispatches to rate_limited events", %{state: state, server: server} do
      payload = %{
        "op" => 0,
        "t" => "RATE_LIMITED",
        "s" => 12,
        "d" => %{
          "opcode" => 8,
          "retry_after" => 60.0,
          "meta" => %{"guild_id" => "guild1", "nonce" => "nonce1"}
        }
      }

      assert {:noreply, %Connection{seq: 12}} = deliver_json(%{state | seq: 11}, server, payload)

      assert_receive {:rate_limited,
                      %{
                        "opcode" => 8,
                        "retry_after" => 60.0,
                        "meta" => %{"guild_id" => "guild1", "nonce" => "nonce1"}
                      }}
    end

    test "inflates zlib-stream messages split across frames", %{state: state, server: server} do
      zlib = :zlib.open()
      :ok = :zlib.deflateInit(zlib)
      payload = %{"op" => 0, "t" => "TYPING_START", "s" => 3, "d" => %{}}
      compressed = IO.iodata_to_binary(:zlib.deflate(zlib, JSON.encode!(payload), :sync))
      :zlib.close(zlib)

      {first, second} = :erlang.split_binary(compressed, div(byte_size(compressed), 2))

      state = %{state | zlib: Lingo.Gateway.Compression.new()}
      {:noreply, state} = deliver(state, server, frame(:binary, first))
      assert state.seq == nil

      {:noreply, state} = deliver(state, server, frame(:binary, second))
      assert state.seq == 3
    end

    test "reconnects on data that doesn't inflate", %{state: state, server: server} do
      state = %{state | zlib: Lingo.Gateway.Compression.new()}

      {:noreply, state} =
        deliver(state, server, frame(:binary, <<"garbage", 0, 0, 0xFF, 0xFF>>))

      assert state.ws == nil
      assert state.state == :disconnected
    end

    test "drops frames that follow a reconnect request", %{state: state, server: server} do
      dispatch = %{"op" => 0, "t" => "TYPING_START", "s" => 9, "d" => %{}}

      {:noreply, state} =
        deliver(state, server, [
          frame(:text, JSON.encode!(%{"op" => 7, "d" => nil})),
          frame(:text, JSON.encode!(dispatch))
        ])

      assert state.ws == nil
      assert state.seq == nil
    end

    test "ignores messages from a previous connection", %{state: state} do
      {old_ws, _old_server} = Server.connect()
      state = %{state | state: :connected}

      assert {:noreply, ^state} = Connection.handle_info({:tcp_closed, old_ws.socket}, state)

      close = IO.iodata_to_binary(frame(:close, <<4000::16>>))
      assert {:noreply, ^state} = Connection.handle_info({:tcp, old_ws.socket, close}, state)
    end

    test "reconnects when the socket closes", %{state: state, server: server} do
      :gen_tcp.close(server)
      assert_receive {:tcp_closed, _socket} = message

      {:noreply, state} = Connection.handle_info(message, %{state | seq: 4, session_id: "s"})
      assert state.ws == nil
      assert state.connect_timer
      assert {state.seq, state.session_id} == {4, "s"}
    end

    test "reconnects on a protocol violation", %{state: state, server: server} do
      {:noreply, state} = deliver(state, server, frame(:text, "masked", mask: <<1, 2, 3, 4>>))
      assert state.ws == nil
      assert state.connect_timer
    end
  end

  describe "close codes" do
    test "a resumable close keeps the session", %{state: state, server: server} do
      state = %{state | seq: 4, session_id: "s"}
      {:noreply, state} = deliver(state, server, frame(:close, <<4000::16>>))

      assert state.ws == nil
      assert {state.seq, state.session_id} == {4, "s"}
    end

    test "an invalid session close drops the session", %{state: state, server: server} do
      state = %{state | seq: 4, session_id: "s"}
      {:noreply, state} = deliver(state, server, frame(:close, <<4007::16>>))

      assert {state.seq, state.session_id} == {nil, nil}
    end

    test "a fatal close stops the connection", %{state: state, server: server} do
      log =
        capture_log(fn ->
          assert {:stop, {:shutdown, {:fatal, 4004}}, state} =
                   deliver(state, server, frame(:close, <<4004::16, "Authentication failed.">>))

          assert state.ws == nil
        end)

      assert log =~ "fatal code 4004"
    end
  end

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
      assert :queue.is_empty(state.send_queue)
    end

    test "sends over the gateway limit wait for the next window", %{state: state, server: server} do
      state = %{
        state
        | state: :connected,
          send_count: 115,
          send_window_start: System.monotonic_time(:millisecond)
      }

      {:noreply, state} = Connection.handle_cast({:send, %{"op" => 3, "d" => %{}}}, state)

      assert sent_payload(server, 100) == nil
      assert state.send_timer
      assert :queue.len(state.send_queue) == 1
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
