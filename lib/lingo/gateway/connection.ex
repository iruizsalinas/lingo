defmodule Lingo.Gateway.Connection do
  @moduledoc false

  use GenServer, restart: :transient

  alias Lingo.Gateway.{Compression, Heartbeat, Payload}

  @fatal_codes [4004, 4010, 4011, 4012, 4013, 4014]
  @session_dead_codes [4003, 4005, 4007, 4008, 4009]
  @hello_timeout 60_000

  # gateway allows 120 sends per 60s, we use 115 as safe margin
  @send_limit 115
  @send_window_ms 60_000

  defstruct [
    :gun_pid,
    :gun_ref,
    :stream_ref,
    :heartbeat_pid,
    :shard_id,
    :shard_count,
    :token,
    :intents,
    :session_id,
    :resume_gateway_url,
    :gateway_url,
    :seq,
    :zlib,
    :hello_timer,
    presence: [],
    state: :disconnected,
    send_count: 0,
    send_window_start: 0
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def send_payload(pid, payload) do
    GenServer.cast(pid, {:send, payload})
  end

  def status(pid) do
    GenServer.call(pid, :status, 2_000)
  catch
    :exit, _ -> :dead
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      shard_id: Keyword.fetch!(opts, :shard_id),
      shard_count: Keyword.fetch!(opts, :shard_count),
      token: Keyword.fetch!(opts, :token),
      intents: Keyword.fetch!(opts, :intents),
      gateway_url: Keyword.get(opts, :gateway_url),
      presence: Keyword.get(opts, :presence, [])
    }

    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.state, state}
  end

  @impl true
  def handle_cast({:send, payload}, state) do
    state = rate_limited_send(state, Payload.encode(payload))
    {:noreply, state}
  end

  @impl true
  def handle_info(:connect, state) do
    host =
      (state.resume_gateway_url || state.gateway_url || "gateway.discord.gg")
      |> String.replace(~r"^wss?://", "")
      |> String.trim_trailing("/")

    {:noreply, do_connect(state, host)}
  end

  def handle_info(:reconnect, state) do
    dispatch_event(state, :shard_reconnecting, %{shard_id: state.shard_id})
    state = close_connection(state)
    Process.send_after(self(), :connect, 1_000 + :rand.uniform(4_000))
    {:noreply, %{state | state: :disconnected}}
  end

  def handle_info(:heartbeat_timeout, %{state: :connected} = state) do
    dispatch_event(state, :shard_reconnecting, %{shard_id: state.shard_id})
    graceful_close(state)
    state = close_connection(state)
    Process.send_after(self(), :connect, 1_000 + :rand.uniform(4_000))
    {:noreply, %{state | state: :disconnected}}
  end

  def handle_info(:hello_timeout, %{state: :awaiting_hello} = state) do
    send(self(), :reconnect)
    {:noreply, state}
  end

  def handle_info(:hello_timeout, state), do: {:noreply, state}

  def handle_info(:heartbeat_timeout, state), do: {:noreply, state}

  def handle_info({:send_heartbeat, seq}, state) do
    # heartbeats bypass send rate limit
    send_frame(state, Payload.encode(Payload.heartbeat(seq)))
    {:noreply, state}
  end

  # :gun messages
  def handle_info({:gun_up, pid, :http}, %{gun_pid: pid} = state) do
    path = "/?v=10&encoding=json&compress=zlib-stream"
    stream_ref = :gun.ws_upgrade(pid, path, [], %{silence_pings: false})
    {:noreply, %{state | stream_ref: stream_ref}}
  end

  def handle_info(
        {:gun_upgrade, pid, ref, ["websocket"], _headers},
        %{gun_pid: pid, stream_ref: ref} = state
      ) do
    timer = Process.send_after(self(), :hello_timeout, @hello_timeout)
    {:noreply, %{state | state: :awaiting_hello, zlib: Compression.new(), hello_timer: timer}}
  end

  def handle_info({:gun_ws, pid, ref, {:binary, data}}, %{gun_pid: pid, stream_ref: ref} = state) do
    case Compression.push(state.zlib, data) do
      {zlib, nil} ->
        {:noreply, %{state | zlib: zlib}}

      {zlib, decompressed} ->
        state = %{state | zlib: zlib}

        case safe_decode(decompressed) do
          {:ok, payload} -> handle_gateway_message(payload, state)
          :error -> {:noreply, state}
        end
    end
  rescue
    _ ->
      send(self(), :reconnect)
      {:noreply, state}
  end

  def handle_info({:gun_ws, pid, ref, {:text, data}}, %{gun_pid: pid, stream_ref: ref} = state) do
    case safe_decode(data) do
      {:ok, payload} -> handle_gateway_message(payload, state)
      :error -> {:noreply, state}
    end
  end

  def handle_info({:gun_ws, _pid, _ref, {:close, code, _reason}}, state) do
    handle_close(state, code)
  end

  def handle_info({:gun_down, _pid, _protocol, _reason, _}, state) do
    send(self(), :reconnect)
    {:noreply, state}
  end

  def handle_info({:gun_error, _pid, _ref, _reason}, state), do: {:noreply, state}

  def handle_info({:gun_response, _pid, _ref, _fin, _status}, state) do
    send(self(), :reconnect)
    {:noreply, state}
  end

  def handle_info({:gun_data, _, _, _, _}, state), do: {:noreply, state}

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{gun_ref: ref} = state) do
    send(self(), :reconnect)
    {:noreply, %{state | gun_pid: nil, gun_ref: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # gateway opcodes

  defp handle_gateway_message(%{"op" => 10, "d" => %{"heartbeat_interval" => interval}}, state) do
    if state.hello_timer, do: Process.cancel_timer(state.hello_timer)
    state = %{state | hello_timer: nil}

    if state.heartbeat_pid && Process.alive?(state.heartbeat_pid) do
      GenServer.stop(state.heartbeat_pid, :normal, 5_000)
    end

    {:ok, hb_pid} =
      Heartbeat.start_link(interval: interval, connection: self(), shard_id: state.shard_id)

    state = %{state | heartbeat_pid: hb_pid}

    if state.session_id && state.seq do
      send_frame(state, Payload.encode(Payload.resume(state.token, state.session_id, state.seq)))
      {:noreply, %{state | state: :resuming}}
    else
      wait_for_identify_slot(state.shard_id)

      payload =
        Payload.identify(
          state.token,
          state.intents,
          state.shard_id,
          state.shard_count,
          state.presence
        )

      send_frame(state, Payload.encode(payload))
      {:noreply, %{state | state: :identifying}}
    end
  end

  defp handle_gateway_message(%{"op" => 0, "t" => event_type, "d" => data, "s" => seq}, state) do
    state = %{state | seq: seq}
    if state.heartbeat_pid, do: Heartbeat.update_seq(state.heartbeat_pid, seq)

    state = handle_dispatch(event_type, data, state)
    {:noreply, state}
  end

  defp handle_gateway_message(%{"op" => 11}, state) do
    if state.heartbeat_pid, do: Heartbeat.ack(state.heartbeat_pid)
    {:noreply, state}
  end

  defp handle_gateway_message(%{"op" => 1}, state) do
    send_frame(state, Payload.encode(Payload.heartbeat(state.seq)))
    {:noreply, state}
  end

  defp handle_gateway_message(%{"op" => 7}, state) do
    dispatch_event(state, :shard_reconnecting, %{shard_id: state.shard_id})
    graceful_close(state)
    state = close_connection(state)
    send(self(), :connect)
    {:noreply, %{state | state: :disconnected}}
  end

  defp handle_gateway_message(%{"op" => 9, "d" => resumable}, state) do
    dispatch_event(state, :shard_reconnecting, %{shard_id: state.shard_id})

    state =
      if resumable do
        state
      else
        %{state | session_id: nil, seq: nil, resume_gateway_url: nil}
      end

    state = close_connection(state)
    delay = 1_000 + :rand.uniform(4_000)
    Process.send_after(self(), :connect, delay)
    {:noreply, %{state | state: :disconnected}}
  end

  defp handle_gateway_message(_msg, state), do: {:noreply, state}

  # dispatch events

  defp handle_dispatch("READY", data, state) do
    application_id = get_in(data, ["application", "id"])
    if application_id, do: Lingo.Config.put(:application_id, application_id)

    %{
      state
      | session_id: data["session_id"],
        resume_gateway_url: data["resume_gateway_url"],
        state: :connected
    }
    |> dispatch_event(:ready, Map.put(data, "shard_id", state.shard_id))
  end

  defp handle_dispatch("RESUMED", _data, state) do
    %{state | state: :connected}
    |> dispatch_event(:resumed, %{shard_id: state.shard_id})
  end

  defp handle_dispatch(event_type, data, state) do
    event_atom = safe_event_atom(event_type)
    dispatch_event(state, event_atom, data)
  end

  defp dispatch_event(state, event, data) do
    Lingo.Gateway.Dispatcher.dispatch(event, data)
    state
  end

  # send rate limiting (120/60s, we cap at 115)

  defp rate_limited_send(state, data) do
    now = System.monotonic_time(:millisecond)

    {count, window_start} =
      if now - state.send_window_start >= @send_window_ms do
        {0, now}
      else
        {state.send_count, state.send_window_start}
      end

    if count >= @send_limit do
      wait = @send_window_ms - (now - window_start) + trunc(:rand.uniform() * 1_500)
      Process.sleep(max(wait, 0))

      rate_limited_send(
        %{state | send_count: 0, send_window_start: System.monotonic_time(:millisecond)},
        data
      )
    else
      send_frame(state, data)
      %{state | send_count: count + 1, send_window_start: window_start}
    end
  end

  # helpers

  defp do_connect(state, host) do
    host_charlist = String.to_charlist(host)

    gun_opts = %{
      protocols: [:http],
      transport: :tls,
      tls_opts: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    }

    case :gun.open(host_charlist, 443, gun_opts) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        %{state | gun_pid: pid, gun_ref: ref, state: :connecting}

      {:error, _reason} ->
        Process.send_after(self(), :connect, 5_000)
        state
    end
  end

  defp send_frame(%{gun_pid: pid, stream_ref: ref}, data) when not is_nil(pid) do
    :gun.ws_send(pid, ref, {:text, data})
  end

  defp send_frame(_, _), do: :ok

  @identify_table :lingo_identify_throttle
  @identify_cooldown_ms 5_500

  defp wait_for_identify_slot(shard_id) do
    try do
      :ets.new(@identify_table, [:named_table, :public, :set])
    rescue
      ArgumentError -> :ok
    end

    max_concurrency = :persistent_term.get(:lingo_max_concurrency, 1)
    bucket = rem(shard_id, max_concurrency)

    case :ets.lookup(@identify_table, bucket) do
      [{_, last_identify}] ->
        elapsed = System.monotonic_time(:millisecond) - last_identify

        if elapsed < @identify_cooldown_ms do
          Process.sleep(@identify_cooldown_ms - elapsed + trunc(:rand.uniform() * 500))
        end

      [] ->
        :ok
    end

    :ets.insert(@identify_table, {bucket, System.monotonic_time(:millisecond)})
  end

  defp safe_decode(data) do
    {:ok, Jason.decode!(data)}
  rescue
    _ -> :error
  end

  defp graceful_close(%{gun_pid: pid, stream_ref: ref}) when not is_nil(pid) do
    :gun.ws_send(pid, ref, {:close, 4000, ""})
  end

  defp graceful_close(_), do: :ok

  defp close_connection(state) do
    if state.hello_timer, do: Process.cancel_timer(state.hello_timer)

    if state.heartbeat_pid && Process.alive?(state.heartbeat_pid) do
      GenServer.stop(state.heartbeat_pid, :normal, 5_000)
    end

    if state.zlib, do: Compression.close(state.zlib)
    if state.gun_pid, do: :gun.close(state.gun_pid)

    %{
      state
      | gun_pid: nil,
        gun_ref: nil,
        stream_ref: nil,
        heartbeat_pid: nil,
        zlib: nil,
        hello_timer: nil
    }
  end

  defp handle_close(state, code) when code in @fatal_codes do
    dispatch_event(state, :shard_error, %{shard_id: state.shard_id, code: code})
    close_connection(state)
    {:stop, {:shutdown, {:fatal, code}}, state}
  end

  defp handle_close(state, code) when code in @session_dead_codes do
    dispatch_event(state, :shard_disconnect, %{shard_id: state.shard_id, code: code})
    state = %{state | session_id: nil, seq: nil, resume_gateway_url: nil}
    send(self(), :reconnect)
    {:noreply, state}
  end

  defp handle_close(state, code) do
    dispatch_event(state, :shard_disconnect, %{shard_id: state.shard_id, code: code})
    send(self(), :reconnect)
    {:noreply, state}
  end

  @known_events %{
    "READY" => :ready,
    "RESUMED" => :resumed,
    "APPLICATION_COMMAND_PERMISSIONS_UPDATE" => :application_command_permissions_update,
    "AUTO_MODERATION_RULE_CREATE" => :auto_moderation_rule_create,
    "AUTO_MODERATION_RULE_UPDATE" => :auto_moderation_rule_update,
    "AUTO_MODERATION_RULE_DELETE" => :auto_moderation_rule_delete,
    "AUTO_MODERATION_ACTION_EXECUTION" => :auto_moderation_action_execution,
    "CHANNEL_CREATE" => :channel_create,
    "CHANNEL_UPDATE" => :channel_update,
    "CHANNEL_DELETE" => :channel_delete,
    "CHANNEL_PINS_UPDATE" => :channel_pins_update,
    "THREAD_CREATE" => :thread_create,
    "THREAD_UPDATE" => :thread_update,
    "THREAD_DELETE" => :thread_delete,
    "THREAD_LIST_SYNC" => :thread_list_sync,
    "THREAD_MEMBER_UPDATE" => :thread_member_update,
    "THREAD_MEMBERS_UPDATE" => :thread_members_update,
    "ENTITLEMENT_CREATE" => :entitlement_create,
    "ENTITLEMENT_UPDATE" => :entitlement_update,
    "ENTITLEMENT_DELETE" => :entitlement_delete,
    "GUILD_CREATE" => :guild_create,
    "GUILD_UPDATE" => :guild_update,
    "GUILD_DELETE" => :guild_delete,
    "GUILD_AUDIT_LOG_ENTRY_CREATE" => :guild_audit_log_entry_create,
    "GUILD_BAN_ADD" => :guild_ban_add,
    "GUILD_BAN_REMOVE" => :guild_ban_remove,
    "GUILD_EMOJIS_UPDATE" => :guild_emojis_update,
    "GUILD_STICKERS_UPDATE" => :guild_stickers_update,
    "GUILD_INTEGRATIONS_UPDATE" => :guild_integrations_update,
    "GUILD_MEMBER_ADD" => :guild_member_add,
    "GUILD_MEMBER_REMOVE" => :guild_member_remove,
    "GUILD_MEMBER_UPDATE" => :guild_member_update,
    "GUILD_MEMBERS_CHUNK" => :guild_members_chunk,
    "GUILD_ROLE_CREATE" => :guild_role_create,
    "GUILD_ROLE_UPDATE" => :guild_role_update,
    "GUILD_ROLE_DELETE" => :guild_role_delete,
    "GUILD_SCHEDULED_EVENT_CREATE" => :guild_scheduled_event_create,
    "GUILD_SCHEDULED_EVENT_UPDATE" => :guild_scheduled_event_update,
    "GUILD_SCHEDULED_EVENT_DELETE" => :guild_scheduled_event_delete,
    "GUILD_SCHEDULED_EVENT_USER_ADD" => :guild_scheduled_event_user_add,
    "GUILD_SCHEDULED_EVENT_USER_REMOVE" => :guild_scheduled_event_user_remove,
    "GUILD_SOUNDBOARD_SOUND_CREATE" => :guild_soundboard_sound_create,
    "GUILD_SOUNDBOARD_SOUND_UPDATE" => :guild_soundboard_sound_update,
    "GUILD_SOUNDBOARD_SOUND_DELETE" => :guild_soundboard_sound_delete,
    "GUILD_SOUNDBOARD_SOUNDS_UPDATE" => :guild_soundboard_sounds_update,
    "SOUNDBOARD_SOUNDS" => :soundboard_sounds,
    "INTEGRATION_CREATE" => :integration_create,
    "INTEGRATION_UPDATE" => :integration_update,
    "INTEGRATION_DELETE" => :integration_delete,
    "INTERACTION_CREATE" => :interaction_create,
    "INVITE_CREATE" => :invite_create,
    "INVITE_DELETE" => :invite_delete,
    "MESSAGE_CREATE" => :message_create,
    "MESSAGE_UPDATE" => :message_update,
    "MESSAGE_DELETE" => :message_delete,
    "MESSAGE_DELETE_BULK" => :message_delete_bulk,
    "MESSAGE_REACTION_ADD" => :message_reaction_add,
    "MESSAGE_REACTION_REMOVE" => :message_reaction_remove,
    "MESSAGE_REACTION_REMOVE_ALL" => :message_reaction_remove_all,
    "MESSAGE_REACTION_REMOVE_EMOJI" => :message_reaction_remove_emoji,
    "MESSAGE_POLL_VOTE_ADD" => :message_poll_vote_add,
    "MESSAGE_POLL_VOTE_REMOVE" => :message_poll_vote_remove,
    "PRESENCE_UPDATE" => :presence_update,
    "STAGE_INSTANCE_CREATE" => :stage_instance_create,
    "STAGE_INSTANCE_UPDATE" => :stage_instance_update,
    "STAGE_INSTANCE_DELETE" => :stage_instance_delete,
    "SUBSCRIPTION_CREATE" => :subscription_create,
    "SUBSCRIPTION_UPDATE" => :subscription_update,
    "SUBSCRIPTION_DELETE" => :subscription_delete,
    "TYPING_START" => :typing_start,
    "USER_UPDATE" => :user_update,
    "VOICE_CHANNEL_EFFECT_SEND" => :voice_channel_effect_send,
    "VOICE_STATE_UPDATE" => :voice_state_update,
    "VOICE_SERVER_UPDATE" => :voice_server_update,
    "WEBHOOKS_UPDATE" => :webhooks_update
  }

  defp safe_event_atom(type) do
    Map.get(@known_events, type, :unknown_event)
  end
end
