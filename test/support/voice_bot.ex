defmodule Lingo.Test.VoiceBot do
  @moduledoc false

  # A bare main-gateway session for one bot, just enough to join a voice
  # channel and collect what Lingo.Voice.Connection needs, so the voice tests
  # can drive three connections directly without a full Lingo bot each.

  use GenServer

  alias Lingo.Gateway.WebSocket

  # GUILDS | GUILD_VOICE_STATES
  @intents 1 + 128

  # not linked: a test must be able to make it leave voice after the test process exits
  def start(token), do: GenServer.start(__MODULE__, token)

  def stop(bot, guild_id) do
    leave_voice(bot, guild_id)
    GenServer.stop(bot)
  end

  @doc "Joins a voice channel; returns the options for Lingo.Voice.Connection."
  def join_voice(bot, guild_id, channel_id),
    do: GenServer.call(bot, {:join, guild_id, channel_id}, 30_000)

  def leave_voice(bot, guild_id), do: GenServer.call(bot, {:leave, guild_id})

  def user_id(bot), do: GenServer.call(bot, :user_id, 30_000)

  @impl true
  def init(token) do
    {:ok, ws} = WebSocket.connect("wss://gateway.discord.gg/?v=10&encoding=json")
    :ok = WebSocket.activate(ws)
    {:ok, %{ws: ws, token: token, seq: nil, user_id: nil, join: nil, voice: %{}, waiting: []}}
  end

  @impl true
  def handle_call(:user_id, from, %{user_id: nil} = state),
    do: {:noreply, %{state | waiting: [from | state.waiting]}}

  def handle_call(:user_id, _from, state), do: {:reply, state.user_id, state}

  def handle_call({:join, guild_id, channel_id}, from, state) do
    state = %{state | join: {from, guild_id, channel_id}, voice: %{}}
    if state.user_id, do: send_join(state)
    {:noreply, state}
  end

  def handle_call({:leave, guild_id}, _from, state) do
    send_json(state, 4, %{guild_id: guild_id, channel_id: nil, self_mute: false, self_deaf: false})

    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    send_json(state, 1, state.seq)
    {:noreply, state}
  end

  def handle_info(message, state) do
    case WebSocket.stream(state.ws, message) do
      {:ok, ws, frames} -> {:noreply, Enum.reduce(frames, %{state | ws: ws}, &handle_frame/2)}
      {:error, _ws, reason} -> {:stop, {:gateway_closed, reason}, state}
      :unknown -> {:noreply, state}
    end
  end

  defp handle_frame({:text, json}, state) do
    message = JSON.decode!(json)
    state = if message["s"], do: %{state | seq: message["s"]}, else: state
    handle_payload(message, state)
  end

  defp handle_frame({:close, code, reason}, _state), do: exit({:gateway_closed, code, reason})
  defp handle_frame(_frame, state), do: state

  # Hello
  defp handle_payload(%{"op" => 10, "d" => %{"heartbeat_interval" => interval}}, state) do
    :timer.send_interval(interval, :heartbeat)

    send_json(state, 2, %{
      token: state.token,
      intents: @intents,
      properties: %{os: "lingo", browser: "lingo", device: "lingo"}
    })

    state
  end

  defp handle_payload(%{"op" => 0, "t" => "READY", "d" => data}, state) do
    user_id = data["user"]["id"]
    Enum.each(state.waiting, &GenServer.reply(&1, user_id))
    state = %{state | user_id: user_id, waiting: []}
    if state.join, do: send_join(state)
    state
  end

  defp handle_payload(
         %{"op" => 0, "t" => "VOICE_STATE_UPDATE", "d" => %{"user_id" => id} = data},
         %{user_id: id} = state
       ),
       do: maybe_reply(%{state | voice: Map.put(state.voice, :session_id, data["session_id"])})

  defp handle_payload(
         %{"op" => 0, "t" => "VOICE_SERVER_UPDATE", "d" => %{"endpoint" => endpoint} = data},
         state
       )
       when is_binary(endpoint),
       do:
         maybe_reply(%{
           state
           | voice: Map.merge(state.voice, %{token: data["token"], endpoint: endpoint})
         })

  defp handle_payload(_payload, state), do: state

  defp maybe_reply(
         %{
           join: {from, guild_id, channel_id},
           voice: %{session_id: _, token: _, endpoint: _} = voice
         } = state
       ) do
    opts = [
      guild_id: guild_id,
      channel_id: channel_id,
      user_id: state.user_id,
      session_id: voice.session_id,
      token: voice.token,
      endpoint: voice.endpoint
    ]

    GenServer.reply(from, {:ok, opts})
    %{state | join: nil}
  end

  defp maybe_reply(state), do: state

  defp send_join(%{join: {_from, guild_id, channel_id}} = state),
    do:
      send_json(state, 4, %{
        guild_id: guild_id,
        channel_id: channel_id,
        self_mute: false,
        self_deaf: false
      })

  defp send_json(state, op, data),
    do: WebSocket.send_frame(state.ws, {:text, JSON.encode!(%{op: op, d: data})})
end
