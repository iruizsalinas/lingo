defmodule Lingo.Voice.ConnectionTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Lingo.Voice.Connection

  test "frames after a voice gateway close cannot advance the resumed sequence" do
    {ws, _server} = Lingo.Test.WebSocketServer.connect()

    state = %Connection{
      guild_id: 100,
      channel_id: 200,
      user_id: 42,
      session_id: "session",
      token: "token",
      endpoint: "127.0.0.1:1",
      ws: ws,
      status: :connected,
      seq: 41
    }

    frames = [
      {:close, 4000, ""},
      {:text, JSON.encode!(%{op: 6, seq: 99, d: %{}})}
    ]

    assert {:noreply, state} = Lingo.Voice.Connection.Signal.handle_frames(frames, state)
    assert state.ws == nil
    assert state.resuming?
    assert state.seq == 41
  end

  test "disconnecting stops a player blocked on its audio source" do
    connection =
      start_supervised!(
        {Connection,
         guild_id: "100",
         channel_id: "200",
         user_id: "42",
         session_id: "session",
         token: "token",
         endpoint: "127.0.0.1:1"}
      )

    :sys.replace_state(connection, &%{&1 | status: :connected, secret_key: <<0::256>>})
    test_pid = self()

    packets =
      Stream.repeatedly(fn ->
        send(test_pid, {:reading_source, self()})

        receive do
          :packet -> <<0xFC, 1>>
        end
      end)

    assert :ok = Connection.play(connection, packets)
    assert_receive {:reading_source, player}
    on_exit(fn -> Process.exit(player, :kill) end)
    ref = Process.monitor(player)

    assert :ok = Connection.disconnect(connection)
    assert_receive {:DOWN, ^ref, :process, ^player, _reason}
  end
end
