defmodule Lingo.Gateway.WebSocketTest do
  use ExUnit.Case, async: true

  alias Lingo.Gateway.WebSocket
  alias Lingo.Gateway.WebSocket.Frame
  alias Lingo.Test.WebSocketServer, as: Server

  defp connect(_context) do
    {ws, server} = Server.connect()
    :ok = WebSocket.activate(ws)
    %{ws: ws, server: server}
  end

  # feeds socket messages to the client until it yields frames or an error
  defp next(ws) do
    receive do
      {tag, _socket, _data} = message when tag in [:tcp, :tcp_error] -> handle(ws, message)
      {:tcp_closed, _socket} = message -> handle(ws, message)
    after
      1_000 -> flunk("no message from the socket")
    end
  end

  defp handle(ws, message) do
    case WebSocket.stream(ws, message) do
      {:ok, ws, []} -> next(ws)
      result -> result
    end
  end

  defp frames(ws) do
    assert {:ok, _ws, frames} = next(ws)
    frames
  end

  describe "exchanging frames" do
    setup :connect

    test "receives server frames and sends masked frames", %{ws: ws, server: server} do
      Server.send_frame(server, :text, "hello")
      assert frames(ws) == [{:text, "hello"}]

      assert :ok = WebSocket.send_frame(ws, {:binary, <<1, 2, 3>>})
      assert Server.recv_frame(server) == {:binary, true, <<1, 2, 3>>}
    end

    test "decodes several frames from one packet", %{ws: ws, server: server} do
      :gen_tcp.send(server, [Frame.encode(:text, "a"), Frame.encode(:binary, "b")])
      assert frames(ws) == [{:text, "a"}, {:binary, "b"}]
    end

    test "buffers a frame that arrives one byte at a time", %{ws: ws, server: server} do
      frame = IO.iodata_to_binary(Frame.encode(:text, :binary.copy("x", 300)))
      for <<byte <- frame>>, do: :gen_tcp.send(server, <<byte>>)

      assert frames(ws) == [{:text, :binary.copy("x", 300)}]
    end

    test "reassembles fragments and answers pings in between", %{ws: ws, server: server} do
      :gen_tcp.send(server, [
        Frame.encode(:text, "he", fin: false),
        Frame.encode(:ping, "are you there"),
        Frame.encode(:continuation, "ll", fin: false),
        Frame.encode(:continuation, "o")
      ])

      assert frames(ws) == [{:text, "hello"}]
      assert Server.recv_frame(server) == {:pong, true, "are you there"}
    end

    test "returns close frames with their code and reason", %{ws: ws, server: server} do
      Server.send_frame(server, :close, <<4004::16, "Authentication failed.">>)
      assert frames(ws) == [{:close, 4004, "Authentication failed."}]
    end

    test "reports a close frame without a code as 1005", %{ws: ws, server: server} do
      Server.send_frame(server, :close, "")
      assert frames(ws) == [{:close, 1005, ""}]
    end

    test "sends close frames", %{ws: ws, server: server} do
      assert :ok = WebSocket.send_frame(ws, {:close, 4000, "bye"})
      assert Server.recv_frame(server) == {:close, true, <<4000::16, "bye">>}
    end

    test "reports a closed socket", %{ws: ws, server: server} do
      :gen_tcp.close(server)
      assert {:error, _ws, :closed} = next(ws)
    end

    test "ignores messages that belong to other sockets", %{ws: ws} do
      assert WebSocket.stream(ws, {:tcp, make_ref(), "data"}) == :unknown
      assert WebSocket.stream(ws, :something_else) == :unknown
    end
  end

  describe "protocol violations" do
    setup :connect

    for {name, frames, reason} <- [
          {"masked server frame", [{:text, "hi", [mask: <<1, 2, 3, 4>>]}], :unexpected_mask},
          {"continuation without a message", [{:continuation, "x", []}],
           :unexpected_continuation},
          {"new message inside a fragmented one", [{:text, "a", [fin: false]}, {:text, "b", []}],
           :interleaved_message},
          {"invalid UTF-8 in a text frame", [{:text, <<0xFF, 0xFE>>, []}], :invalid_utf8},
          {"invalid UTF-8 in a fragmented text message",
           [{:text, <<0xE2, 0x82>>, [fin: false]}, {:continuation, <<0xFF>>, []}], :invalid_utf8},
          {"one byte close payload", [{:close, <<1>>, []}], :invalid_close_payload},
          {"reserved close code", [{:close, <<1005::16>>, []}], :invalid_close_code},
          {"unassigned close code", [{:close, <<2000::16>>, []}], :invalid_close_code},
          {"invalid UTF-8 close reason", [{:close, <<1000::16, 0xFF>>, []}], :invalid_utf8}
        ] do
      test "rejects #{name}", %{ws: ws, server: server} do
        for {opcode, payload, opts} <- unquote(Macro.escape(frames)) do
          Server.send_frame(server, opcode, payload, opts)
        end

        assert {:error, _ws, unquote(reason)} = next(ws)
      end
    end

    test "rejects frames and messages over max_frame_size" do
      {ws, server} = Server.connect(max_frame_size: 4)
      :ok = WebSocket.activate(ws)

      Server.send_frame(server, :text, "12345")
      assert {:error, _ws, :frame_too_large} = next(ws)

      {ws, server} = Server.connect(max_frame_size: 4)
      :ok = WebSocket.activate(ws)

      Server.send_frame(server, :text, "123", fin: false)
      Server.send_frame(server, :continuation, "45")
      assert {:error, _ws, :message_too_large} = next(ws)
    end
  end

  describe "opening handshake" do
    test "delivers frames sent right after the handshake response" do
      respond = fn key -> [Server.accept_response(key), Frame.encode(:text, "early")] end
      {ws, _server} = Server.connect(respond: respond)
      :ok = WebSocket.activate(ws)

      assert frames(ws) == [{:text, "early"}]
    end

    test "accepts headers in any case and with several tokens" do
      respond = fn key ->
        [
          "HTTP/1.1 101 Switching Protocols\r\n",
          "UPGRADE: WebSocket\r\n",
          "connection: keep-alive, upgrade\r\n",
          "sec-websocket-accept: #{Server.accept_key(key)}\r\n\r\n"
        ]
      end

      assert {:ok, _ws, _server} = Server.try_connect(respond: respond)
    end

    for {name, response, reason} <- [
          {"a wrong accept key",
           "HTTP/1.1 101 OK\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: bm9wZQ==\r\n\r\n",
           :invalid_accept},
          {"a non-101 status", "HTTP/1.1 403 Forbidden\r\ncontent-length: 0\r\n\r\n",
           {:unexpected_status, 403}},
          {"a missing upgrade header", "HTTP/1.1 101 OK\r\nConnection: Upgrade\r\n\r\n",
           :invalid_upgrade_header},
          {"a missing connection header", "HTTP/1.1 101 OK\r\nUpgrade: websocket\r\n\r\n",
           :invalid_connection_header}
        ] do
      test "fails on #{name}" do
        response = unquote(response)

        assert {:error, unquote(reason), _server} =
                 Server.try_connect(respond: fn _ -> response end)
      end
    end

    test "fails when the server picks an extension we didn't offer" do
      respond = fn key ->
        [
          "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n",
          "Sec-WebSocket-Accept: #{Server.accept_key(key)}\r\n",
          "Sec-WebSocket-Extensions: permessage-deflate\r\n\r\n"
        ]
      end

      assert {:error, :unexpected_extension, _server} = Server.try_connect(respond: respond)
    end

    test "fails on a response that isn't HTTP" do
      assert {:error, {:invalid_response, _}, _server} =
               Server.try_connect(respond: fn _ -> "SSH-2.0-OpenSSH\r\n\r\n" end)
    end

    test "fails on too many headers" do
      headers = for i <- 1..101, do: "x-header-#{i}: value\r\n"
      response = ["HTTP/1.1 101 OK\r\n", headers, "\r\n"]

      assert {:error, :too_many_headers, _server} =
               Server.try_connect(respond: fn _ -> response end)
    end

    test "fails on a header line that is too long" do
      response = ["HTTP/1.1 101 OK\r\nx-big: ", :binary.copy("a", 10_000), "\r\n\r\n"]
      assert {:error, _reason, _server} = Server.try_connect(respond: fn _ -> response end)
    end

    test "times out when the server never answers" do
      respond = fn _key ->
        Process.sleep(300)
        ""
      end

      assert {:error, :timeout, _server} = Server.try_connect(respond: respond, timeout: 100)
    end

    test "fails on unsupported URLs" do
      assert {:error, {:invalid_url, "http://example.com"}} =
               WebSocket.connect("http://example.com")

      assert {:error, {:invalid_url, "wss://"}} = WebSocket.connect("wss://")
    end

    test "fails when nothing is listening" do
      {:ok, listen} = :gen_tcp.listen(0, [])
      {:ok, port} = :inet.port(listen)
      :gen_tcp.close(listen)

      assert {:error, :econnrefused} = WebSocket.connect("ws://127.0.0.1:#{port}")
    end
  end
end
