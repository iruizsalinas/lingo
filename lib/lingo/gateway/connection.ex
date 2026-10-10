defmodule Lingo.Gateway.Connection do
  @moduledoc false

  # One shard's connection to the main gateway. This module holds the process
  # and decodes frames; Protocol decides what each payload means and
  # Transport owns the socket.

  use GenServer, restart: :transient

  alias Lingo.Gateway.{Compression, Payload, WebSocket}
  alias Lingo.Gateway.Connection.{Outbox, Protocol, Transport}

  defstruct [
    :bot,
    :ws,
    :connect_task,
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
    :connect_timer,
    :identify_timer,
    :send_timer,
    presence: [],
    state: :disconnected,
    outbox: %Outbox{}
  ]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def send_payload(pid, payload), do: GenServer.cast(pid, {:send, payload})

  def update_presence(pid, presence), do: GenServer.cast(pid, {:update_presence, presence})

  def status(pid) do
    GenServer.call(pid, :status, 2_000)
  catch
    :exit, _ -> :dead
  end

  @impl true
  def init(opts) do
    bot = Keyword.fetch!(opts, :bot)
    Lingo.Instance.put_current(bot)

    state = %__MODULE__{
      bot: bot,
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
  def handle_call(:status, _from, state), do: {:reply, state.state, state}

  @impl true
  def handle_cast({:send, payload}, state),
    do: {:noreply, Transport.enqueue(state, Payload.encode(payload))}

  def handle_cast({:update_presence, presence}, state) do
    status = presence[:status] || :online
    payload = Payload.presence_update(status, presence[:text], presence[:activity])
    {:noreply, Transport.enqueue(%{state | presence: presence}, Payload.encode(payload))}
  end

  @impl true
  def handle_info(:connect, %{ws: nil, connect_task: nil} = state),
    do: {:noreply, Transport.start_connect(%{state | connect_timer: nil})}

  def handle_info(:connect, state), do: {:noreply, %{state | connect_timer: nil}}

  def handle_info(:reconnect, state), do: {:noreply, Transport.reconnect(state)}

  # zombied connection: close with a non-1000 code so the session stays resumable
  def handle_info(:heartbeat_timeout, %{ws: %WebSocket{}} = state) do
    Transport.graceful_close(state)
    {:noreply, Transport.reconnect(state)}
  end

  def handle_info(:heartbeat_timeout, state), do: {:noreply, state}

  def handle_info(:hello_timeout, %{state: :awaiting_hello} = state),
    do: {:noreply, Transport.reconnect(state)}

  def handle_info(:hello_timeout, state), do: {:noreply, state}

  def handle_info(:send_heartbeat, state) do
    Transport.send_frame(state, Payload.encode(Payload.heartbeat(state.seq)))
    {:noreply, state}
  end

  def handle_info(:identify, %{ws: %WebSocket{}} = state) do
    identify =
      Payload.identify(
        state.token,
        state.intents,
        state.shard_id,
        state.shard_count,
        state.presence
      )

    Transport.send_frame(state, Payload.encode(identify))
    {:noreply, %{state | identify_timer: nil, state: :identifying}}
  end

  def handle_info(:identify, state), do: {:noreply, %{state | identify_timer: nil}}

  def handle_info(:flush_send, state), do: {:noreply, Transport.flush(%{state | send_timer: nil})}

  def handle_info({ref, result}, %{connect_task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    state = %{state | connect_task: nil}

    case result do
      {:ok, ws} -> {:noreply, Transport.connected(%{state | ws: ws})}
      {:error, _reason} -> {:noreply, Transport.reconnect(state)}
    end
  end

  # anything else may come from the socket, stream/2 ignores messages that
  # belong to an older connection
  def handle_info(message, %{ws: %WebSocket{} = ws} = state) do
    case WebSocket.stream(ws, message) do
      {:ok, ws, frames} -> handle_frames(frames, %{state | ws: ws})
      {:error, _ws, _reason} -> {:noreply, Transport.reconnect(state)}
      :unknown -> {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp handle_frames([], state), do: {:noreply, state}

  defp handle_frames([frame | rest], state) do
    ws = state.ws

    case handle_frame(frame, state) do
      # frames left over from a connection that was just dropped are stale
      {:noreply, %{ws: ^ws} = state} -> handle_frames(rest, state)
      result -> result
    end
  end

  defp handle_frame({:binary, data}, state) do
    case inflate(state.zlib, data) do
      {:ok, zlib, nil} -> {:noreply, %{state | zlib: zlib}}
      {:ok, zlib, json} -> handle_json(json, %{state | zlib: zlib})
      :error -> {:noreply, Transport.reconnect(state)}
    end
  end

  defp handle_frame({:text, json}, state), do: handle_json(json, state)
  defp handle_frame({:close, code, _reason}, state), do: Protocol.close(state, code)

  defp inflate(zlib, data) do
    {zlib, json} = Compression.push(zlib, data)
    {:ok, zlib, json}
  rescue
    ErlangError -> :error
  end

  defp handle_json(json, state) do
    case JSON.decode(json) do
      {:ok, payload} -> Protocol.handle(payload, state)
      {:error, _reason} -> {:noreply, state}
    end
  end
end
