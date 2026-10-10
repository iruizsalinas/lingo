defmodule Lingo.Gateway.ConnectionTest do
  use ExUnit.Case, async: true

  import Bitwise
  import ExUnit.CaptureLog

  alias Lingo.Gateway.{Connection, WebSocket}
  alias Lingo.Test.WebSocketServer, as: Server

  defmodule EventBot do
    use Lingo.Bot

    @impl true
    def handle_event(:rate_limited, data),
      do: send(Lingo.Instance.get(:test_pid), {:rate_limited, data})
  end

  setup do
    bot =
      Lingo.TestBot.start(
        bot: EventBot,
        test_pid: self(),
        start: [:cache, :collector, :identify, :sessions]
      )

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

      state = %{state | inflate: Lingo.Gateway.Compression.new()}
      {:noreply, state} = deliver(state, server, frame(:binary, first))
      assert state.seq == nil

      {:noreply, state} = deliver(state, server, frame(:binary, second))
      assert state.seq == 3
    end

    test "reconnects on data that doesn't inflate", %{state: state, server: server} do
      state = %{state | inflate: Lingo.Gateway.Compression.new()}

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

  describe "encodings" do
    test "decodes ETF frames", %{state: state, server: server} do
      payload = %{
        op: 0,
        t: :RATE_LIMITED,
        s: 3,
        d: %{opcode: 8, retry_after: 1.5, meta: %{guild_id: 1 <<< 40}}
      }

      state = %{state | encoding: :etf}

      {:noreply, state} = deliver(state, server, frame(:binary, :erlang.term_to_binary(payload)))

      assert state.seq == 3
      guild_id = Integer.to_string(1 <<< 40)
      assert_receive {:rate_limited, %{"opcode" => 8, "meta" => %{"guild_id" => ^guild_id}}}
    end
  end

  describe "sessions" do
    test "a restarted connection picks up its stored session", %{state: state} do
      Lingo.Gateway.Sessions.put(state.bot, 0, 1, "s1", "wss://resume", 41)

      {:ok, restored} =
        Connection.init(bot: state.bot, shard_id: 0, shard_count: 1, token: "t", intents: 1)

      assert {restored.session_id, restored.resume_gateway_url, restored.seq} ==
               {"s1", "wss://resume", 41}

      assert_receive :connect
    end

    test "READY stores the session and dispatches move its seq", %{state: state, server: server} do
      ready = %{
        "op" => 0,
        "t" => "READY",
        "s" => 1,
        "d" => %{"session_id" => "s1", "resume_gateway_url" => "wss://resume"}
      }

      {:noreply, state} = deliver_json(%{state | state: :identifying}, server, ready)
      assert Lingo.Gateway.Sessions.fetch(state.bot, 0, 1) == {"s1", "wss://resume", 1}

      typing = %{"op" => 0, "t" => "TYPING_START", "s" => 2, "d" => %{}}
      {:noreply, state} = deliver_json(state, server, typing)
      assert Lingo.Gateway.Sessions.fetch(state.bot, 0, 1) == {"s1", "wss://resume", 2}

      {:noreply, _state} = deliver_json(state, server, %{"op" => 9, "d" => false})
      assert Lingo.Gateway.Sessions.fetch(state.bot, 0, 1) == nil
    end

    test "a shard whose count isn't the live one delivers nothing", %{
      state: state,
      server: server
    } do
      Lingo.Instance.put(state.bot, :shard_count, 2)
      payload = %{"op" => 0, "t" => "RATE_LIMITED", "s" => 1, "d" => %{"opcode" => 8}}

      {:noreply, state} = deliver_json(state, server, payload)
      assert state.seq == 1
      refute state.joined
      refute_receive {:rate_limited, _}, 100
    end
  end
end
