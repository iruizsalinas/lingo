defmodule Lingo.Test.FakeGateway do
  @moduledoc false

  # Stands in for Discord's gateway, for tests that start whole bots. It
  # accepts any number of connections on one port and speaks whichever
  # encoding and compression each connection asks for in its URL.
  #
  # Every connection says Hello, answers heartbeats, Identify (with READY,
  # unless auto_ready is off) and Resume (with RESUMED), and reports to the
  # test process:
  #
  #   {:identified, conn, shard_id, shard_count}
  #   {:resumed, conn, session_id, seq}
  #   {:op, conn, op, data}     any other payload
  #   {:closed, conn}
  #
  # Tests drive a connection with ready/1, dispatch/3 and drop/1.

  alias Lingo.Gateway.WebSocket.Frame
  alias Lingo.Test.WebSocketServer

  def start(test_pid) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    url = "ws://127.0.0.1:#{port}"
    {:ok, config} = Agent.start_link(fn -> %{auto_ready: true} end)
    acceptor = spawn_link(fn -> accept_loop(listen, test_pid, url, config) end)
    :ok = :gen_tcp.controlling_process(listen, acceptor)
    %{url: url, config: config}
  end

  def auto_ready(gateway, on?), do: Agent.update(gateway.config, &%{&1 | auto_ready: on?})

  def ready(conn), do: send(conn, :ready)
  def dispatch(conn, type, data), do: send(conn, {:dispatch, type, data})
  def drop(conn), do: send(conn, :drop)

  defp accept_loop(listen, test_pid, url, config) do
    {:ok, socket} = :gen_tcp.accept(listen)
    pid = spawn(fn -> receive(do: (:go -> connection(socket, test_pid, url, config))) end)
    :ok = :gen_tcp.controlling_process(socket, pid)
    send(pid, :go)
    accept_loop(listen, test_pid, url, config)
  end

  defp connection(socket, test_pid, url, config) do
    query = handshake(socket)

    state = %{
      socket: socket,
      test: test_pid,
      url: url,
      config: config,
      encoding: query["encoding"] || "json",
      zlib: if(query["compress"] == "zlib-stream", do: deflate()),
      zstd: query["compress"] == "zstd-stream",
      seq: 0,
      session: nil,
      buffer: <<>>
    }

    push(state, %{op: 10, d: %{heartbeat_interval: 45_000}})
    :ok = :inet.setopts(socket, active: :once)
    loop(state)
  end

  defp loop(state) do
    receive do
      {:tcp, _socket, data} ->
        :ok = :inet.setopts(state.socket, active: :once)
        state |> frames(state.buffer <> data) |> loop()

      {:tcp_closed, _socket} ->
        send(state.test, {:closed, self()})

      :ready ->
        loop(ready_dispatch(state))

      {:dispatch, type, data} ->
        loop(push_dispatch(state, type, data))

      :drop ->
        :gen_tcp.close(state.socket)
        send(state.test, {:closed, self()})
    end
  end

  defp frames(state, buffer) do
    case Frame.decode(buffer, masked: true) do
      {:ok, {:close, _fin, _payload}, _rest} -> state
      {:ok, {_opcode, _fin, payload}, rest} -> state |> handle(decode(payload)) |> frames(rest)
      :more -> %{state | buffer: buffer}
    end
  end

  defp handle(state, %{"op" => 1}), do: push(state, %{op: 11, d: nil})

  defp handle(state, %{"op" => 2, "d" => %{"shard" => [id, count]}}) do
    send(state.test, {:identified, self(), id, count})
    state = %{state | session: "s#{id}-#{count}-#{System.unique_integer([:positive])}"}
    if Agent.get(state.config, & &1.auto_ready), do: ready_dispatch(state), else: state
  end

  defp handle(state, %{"op" => 6, "d" => %{"session_id" => session, "seq" => seq}}) do
    send(state.test, {:resumed, self(), session, seq})
    push_dispatch(%{state | session: session, seq: seq}, "RESUMED", %{})
  end

  defp handle(state, %{"op" => op, "d" => data}) do
    send(state.test, {:op, self(), op, data})
    state
  end

  defp ready_dispatch(state) do
    push_dispatch(state, "READY", %{
      session_id: state.session,
      resume_gateway_url: state.url,
      user: %{id: "100", username: "lingo"},
      application: %{id: "200"},
      guilds: []
    })
  end

  defp push_dispatch(state, type, data) do
    state = %{state | seq: state.seq + 1}
    push(state, %{op: 0, t: type, s: state.seq, d: data})
  end

  defp push(state, payload) do
    {opcode, data} = encode(state.encoding, payload)
    data = compress(state, data)
    opcode = if state.zlib || state.zstd, do: :binary, else: opcode
    :ok = WebSocketServer.send_frame(state.socket, opcode, data)
    state
  end

  # Discord's ETF uses atom keys and nil
  defp encode("etf", payload), do: {:binary, :erlang.term_to_binary(payload)}
  defp encode("json", payload), do: {:text, JSON.encode!(payload)}

  defp decode(<<131, _::binary>> = data), do: :erlang.binary_to_term(data)
  defp decode(data), do: JSON.decode!(data)

  defp compress(%{zlib: nil, zstd: false}, data), do: data
  defp compress(%{zstd: true}, data), do: IO.iodata_to_binary(:zstd.compress(data))
  defp compress(%{zlib: z}, data), do: IO.iodata_to_binary(:zlib.deflate(z, data, :sync))

  defp deflate do
    z = :zlib.open()
    :ok = :zlib.deflateInit(z)
    z
  end

  defp handshake(socket) do
    :ok = :inet.setopts(socket, packet: :http_bin)
    {:ok, {:http_request, :GET, {:abs_path, target}, _}} = :gen_tcp.recv(socket, 0, 5_000)
    :ok = :inet.setopts(socket, packet: :httph_bin)
    key = read_key(socket)
    :ok = :inet.setopts(socket, packet: :raw)
    :ok = :gen_tcp.send(socket, WebSocketServer.accept_response(key))
    URI.decode_query(URI.parse(target).query || "")
  end

  defp read_key(socket, key \\ nil) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, {:http_header, _, name, _, value}} ->
        read_key(
          socket,
          if(String.downcase(to_string(name)) == "sec-websocket-key", do: value, else: key)
        )

      {:ok, :http_eoh} ->
        key
    end
  end
end
