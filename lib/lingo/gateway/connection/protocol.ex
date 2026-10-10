defmodule Lingo.Gateway.Connection.Protocol do
  @moduledoc false

  # What a gateway connection does with each payload Discord sends: the
  # opcodes, the dispatches that change the session, and close codes.

  require Logger

  alias Lingo.Gateway.{Dispatcher, Events, Heartbeat, Payload, ShardManager}
  alias Lingo.Gateway.Connection.Transport

  @fatal_codes [4004, 4010, 4011, 4012, 4013, 4014]
  @session_dead_codes [4003, 4005, 4007, 4008, 4009]

  # Hello: start heartbeating, then resume or identify
  def handle(%{"op" => 10, "d" => %{"heartbeat_interval" => interval}}, state) do
    if state.hello_timer, do: Process.cancel_timer(state.hello_timer)
    state = Transport.stop_heartbeat(%{state | hello_timer: nil})

    {:ok, heartbeat} =
      Heartbeat.start_link(
        bot: state.bot,
        interval: interval,
        connection: self(),
        shard_id: state.shard_id
      )

    state = %{state | heartbeat_pid: heartbeat}

    if state.session_id && state.seq do
      resume = Payload.resume(state.token, state.session_id, state.seq)
      Transport.send_frame(state, Payload.encode(resume))
      {:noreply, %{state | state: :resuming}}
    else
      # wait for an identify slot without blocking, so heartbeats keep flowing
      delay = ShardManager.reserve_identify(state.shard_id)
      timer = Process.send_after(self(), :identify, delay)
      {:noreply, %{state | state: :waiting_to_identify, identify_timer: timer}}
    end
  end

  def handle(%{"op" => 0, "t" => type, "d" => data, "s" => seq}, state),
    do: {:noreply, dispatch(type, data, %{state | seq: seq || state.seq})}

  # Heartbeat ACK
  def handle(%{"op" => 11}, state) do
    if state.heartbeat_pid, do: Heartbeat.ack(state.heartbeat_pid)
    {:noreply, state}
  end

  # Discord asks for a heartbeat now
  def handle(%{"op" => 1}, state) do
    Transport.send_frame(state, Payload.encode(Payload.heartbeat(state.seq)))
    {:noreply, state}
  end

  # Reconnect
  def handle(%{"op" => 7}, state) do
    Transport.graceful_close(state)
    {:noreply, Transport.reconnect(state, 0)}
  end

  # Invalid Session
  def handle(%{"op" => 9, "d" => resumable}, state) do
    state = if resumable, do: state, else: forget_session(state)
    {:noreply, Transport.reconnect(state)}
  end

  def handle(_payload, state), do: {:noreply, state}

  def close(state, code) when code in @fatal_codes do
    Logger.error("Lingo shard #{state.shard_id} closed with fatal code #{code}, not reconnecting")
    Dispatcher.dispatch(:shard_error, %{shard_id: state.shard_id, code: code})
    {:stop, {:shutdown, {:fatal, code}}, %{Transport.close(state) | state: :disconnected}}
  end

  def close(state, code) when code in @session_dead_codes do
    Dispatcher.dispatch(:shard_disconnect, %{shard_id: state.shard_id, code: code})
    {:noreply, Transport.reconnect(forget_session(state))}
  end

  def close(state, code) do
    Dispatcher.dispatch(:shard_disconnect, %{shard_id: state.shard_id, code: code})
    {:noreply, Transport.reconnect(state)}
  end

  defp dispatch("READY", data, state) do
    if id = get_in(data, ["application", "id"]),
      do: Lingo.Instance.put(state.bot, :application_id, id)

    if id = get_in(data, ["user", "id"]), do: Lingo.Instance.put(state.bot, :user_id, id)

    state = %{
      state
      | session_id: data["session_id"],
        resume_gateway_url: data["resume_gateway_url"],
        state: :connected
    }

    Dispatcher.dispatch(:shard_ready, Map.put(data, "shard_id", state.shard_id))
    ShardManager.shard_ready(state.shard_id)
    Transport.flush(state)
  end

  defp dispatch("RESUMED", _data, state) do
    Dispatcher.dispatch(:shard_resumed, %{shard_id: state.shard_id})
    Transport.flush(%{state | state: :connected})
  end

  defp dispatch(type, data, state) do
    Dispatcher.dispatch(Events.name(type), data)
    state
  end

  defp forget_session(state), do: %{state | session_id: nil, seq: nil, resume_gateway_url: nil}
end
