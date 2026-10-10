defmodule Lingo.Voice.Connection.Opcodes do
  @moduledoc false

  # What a voice connection does with each voice gateway opcode.

  alias Lingo.Voice.{Connection, RTP}
  alias Lingo.Voice.Connection.{Media, Playback, Signal}
  alias Lingo.Voice.Dave.Session, as: Dave

  # Hello
  def handle(8, %{"heartbeat_interval" => interval}, state) do
    if state.heartbeat_timer, do: Process.cancel_timer(state.heartbeat_timer)
    send(self(), :heartbeat)
    {:noreply, %{state | heartbeat_interval: trunc(interval), awaiting_ack?: false}}
  end

  # Ready: open the UDP socket and find our public address
  def handle(2, %{"ssrc" => ssrc, "ip" => ip, "port" => port, "modes" => modes}, state) do
    with mode when mode != nil <- RTP.choose_mode(modes),
         {:ok, address} <- :inet.parse_address(String.to_charlist(ip)),
         {:ok, udp} <- :gen_udp.open(0, [:binary, active: true]) do
      if state.udp, do: :gen_udp.close(state.udp)
      send(self(), :discover)

      {:noreply,
       %{
         state
         | ssrc: ssrc,
           mode: mode,
           udp: udp,
           remote: {address, port},
           status: :discovering,
           discovery_attempts: 0
       }}
    else
      error -> {:stop, {:shutdown, {:udp_setup_failed, error}}, state}
    end
  end

  # Session Description: transport key and DAVE version
  def handle(4, %{"secret_key" => key, "mode" => mode} = data, state) do
    {dave, messages} =
      Dave.set_protocol_version(state.dave, data["dave_protocol_version"] || 0, Connection.now())

    Media.schedule_keepalive()

    state = %{
      state
      | secret_key: :binary.list_to_bin(key),
        mode: mode,
        dave: dave,
        status: :connected,
        attempts: 0
    }

    {:noreply, state |> Signal.send_dave(messages) |> Playback.check_ready()}
  end

  # Speaking: also how we learn which user an SSRC belongs to
  def handle(5, %{"user_id" => user_id, "ssrc" => ssrc} = data, state) do
    user_id = Connection.to_integer(user_id)
    Connection.notify(state, {:speaking, user_id, data["speaking"]})

    # a speaker's first packets often beat this message here; hear them now
    {early, unmapped} = Map.pop(state.unmapped, ssrc, [])
    state = %{state | ssrc_users: Map.put(state.ssrc_users, ssrc, user_id), unmapped: unmapped}

    early
    |> Enum.reverse()
    |> Enum.reduce(state, fn {header, opus}, state ->
      Media.deliver(state, user_id, header, opus)
    end)
    |> then(&{:noreply, &1})
  end

  # Heartbeat ACK
  def handle(6, _data, state), do: {:noreply, %{state | awaiting_ack?: false}}

  # Resumed
  def handle(9, _data, state),
    do:
      {:noreply,
       Playback.check_ready(%{state | resuming?: false, status: :connected, attempts: 0})}

  # Clients Connect
  def handle(11, %{"user_ids" => user_ids}, state),
    do:
      {:noreply,
       %{
         state
         | dave: Dave.clients_connect(state.dave, Enum.map(user_ids, &Connection.to_integer/1))
       }}

  # Client Disconnect
  def handle(13, %{"user_id" => user_id}, state) do
    user_id = Connection.to_integer(user_id)
    ssrc_users = Map.reject(state.ssrc_users, fn {_ssrc, id} -> id == user_id end)

    {:noreply,
     %{state | dave: Dave.client_disconnect(state.dave, user_id), ssrc_users: ssrc_users}}
  end

  # DAVE transitions and epochs
  def handle(op, data, state) when op in [21, 22, 24] and is_map(data) do
    {dave, messages} = Dave.handle_json(state.dave, op, data, Connection.now())
    {:noreply, %{state | dave: dave} |> Signal.send_dave(messages) |> Playback.check_ready()}
  end

  def handle(_op, _data, state), do: {:noreply, state}
end
