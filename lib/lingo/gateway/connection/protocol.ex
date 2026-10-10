defmodule Lingo.Gateway.Connection.Protocol do
  @moduledoc false

  # What a gateway connection does with each payload Discord sends: the
  # opcodes, the dispatches that change the session, and close codes.

  require Logger

  alias Lingo.Event.Catalog
  alias Lingo.Gateway.{Connection, Dispatcher, Heartbeat, Identify, Payload}
  alias Lingo.Gateway.{Sessions, ShardManager}
  alias Lingo.Gateway.Connection.Transport
  alias Lingo.Telemetry

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
      Transport.send_frame(state, Payload.resume(state.token, state.session_id, state.seq))
      {:noreply, %{state | state: :resuming}}
    else
      {:noreply, wait_to_identify(state)}
    end
  end

  def handle(%{"op" => 0, "t" => type, "d" => data, "s" => seq}, state) do
    state = %{state | seq: seq || state.seq}

    if seq && state.session_id,
      do: Sessions.seq(state.bot, state.shard_id, state.shard_count, seq)

    {:noreply, dispatch(type, data, state)}
  end

  # Heartbeat ACK
  def handle(%{"op" => 11}, state) do
    if state.heartbeat_pid, do: Heartbeat.ack(state.heartbeat_pid)
    {:noreply, state}
  end

  # Discord asks for a heartbeat now
  def handle(%{"op" => 1}, state) do
    Transport.send_frame(state, Payload.heartbeat(state.seq))
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

  @doc "Sends Identify, once the shard's slot has come."
  def identify(state) do
    identify =
      Payload.identify(
        state.token,
        state.intents,
        state.shard_id,
        state.shard_count,
        state.presence
      )

    Transport.send_frame(state, identify)
    Telemetry.execute([:shard, :identify], %{wait: state.identify_wait}, meta(state))
    %{state | state: :identifying}
  end

  # waits for an identify slot without blocking, so heartbeats keep flowing;
  # with none to be had soon, disconnects and asks again later
  defp wait_to_identify(state) do
    case Identify.reserve(state.shard_id) do
      {:ok, delay} ->
        timer = Process.send_after(self(), :identify, delay)
        %{state | state: :waiting_to_identify, identify_timer: timer, identify_wait: delay}

      {:wait, ms} ->
        Transport.reconnect(state, ms)
    end
  end

  def close(state, code) when code in @fatal_codes do
    Logger.error("Lingo shard #{state.shard_id} closed with fatal code #{code}, not reconnecting")
    disconnected(state, code, true)
    state = forget_session(state)
    {:stop, {:shutdown, {:fatal, code}}, %{Transport.close(state) | state: :disconnected}}
  end

  def close(state, code) when code in @session_dead_codes do
    disconnected(state, code)
    {:noreply, Transport.reconnect(forget_session(state))}
  end

  def close(state, code) do
    disconnected(state, code)
    {:noreply, Transport.reconnect(state)}
  end

  @doc "The socket went away without a close frame."
  def dropped(state) do
    disconnected(state, nil)
    Transport.reconnect(state)
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

    if state.session_id && state.resume_gateway_url do
      Sessions.put(
        state.bot,
        state.shard_id,
        state.shard_count,
        state.session_id,
        state.resume_gateway_url,
        state.seq || 0
      )
    end

    deliver(state, :ready, Map.put(data, "shard", [state.shard_id, state.shard_count]))
    ready(state, false)
  end

  defp dispatch("RESUMED", _data, state) do
    ensure_user_id(state.bot)
    Sessions.save(state.bot, state.shard_id, state.shard_count)
    deliver(state, :resumed, %{"shard" => [state.shard_id, state.shard_count]})
    ready(%{state | state: :connected}, true)
  end

  defp dispatch(type, data, state) do
    state = Connection.maybe_join(state)
    deliver(state, Catalog.gateway_name(type), data)
    state
  end

  defp ready(state, resumed) do
    ShardManager.shard_ready(state.shard_id, state.shard_count)
    Telemetry.execute([:shard, :ready], %{}, Map.put(meta(state), :resumed, resumed))
    Transport.flush(state)
  end

  # events reach the bot only from live shards
  defp deliver(state, event, data) do
    if Connection.live?(state), do: Dispatcher.dispatch(event, data)
  end

  # a session resumed after a full restart never saw READY, which names the bot
  defp ensure_user_id(bot) do
    if Lingo.Instance.get(bot, :user_id, nil) == nil do
      Task.Supervisor.start_child(Lingo.Instance.process_name(bot, Lingo.TaskSupervisor), fn ->
        Lingo.Instance.put_current(bot)

        with {:ok, user} <- Lingo.Api.User.get_current(),
             do: Lingo.Instance.put(bot, :user_id, user.id)
      end)
    end
  catch
    :exit, _no_task_supervisor -> :ok
  end

  defp disconnected(state, code, fatal \\ false) do
    meta = Map.merge(meta(state), %{code: code, fatal: fatal})
    Telemetry.execute([:shard, :disconnected], %{}, meta)
  end

  defp meta(state), do: %{shard_id: state.shard_id, shard_count: state.shard_count}

  defp forget_session(state) do
    Sessions.delete(state.bot, state.shard_id, state.shard_count)
    %{state | session_id: nil, seq: nil, resume_gateway_url: nil}
  end
end
