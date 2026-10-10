defmodule Lingo.Gateway.Connection do
  @moduledoc false

  # One shard's connection to the main gateway. This module holds the process
  # and decodes frames; Protocol decides what each payload means and
  # Transport owns the socket.
  #
  # A connection whose shard count isn't the bot's live one (the new shards
  # of a reshard in progress) keeps its session up but delivers nothing,
  # until the shard manager makes its count the live one.

  use GenServer, restart: :transient

  alias Lingo.Gateway.{Codec, Compression, Groups, Payload, Sessions, WebSocket}
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
    :inflate,
    :hello_timer,
    :connect_timer,
    :identify_timer,
    :send_timer,
    identify_wait: 0,
    encoding: :json,
    compression: :zlib,
    joined: false,
    presence: [],
    state: :disconnected,
    outbox: %Outbox{}
  ]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def send_payload(pid, payload), do: GenServer.cast(pid, {:send, payload})

  def update_presence(pid, presence), do: GenServer.cast(pid, {:update_presence, presence})

  @doc "Tells a connection its shard count just became the live one."
  def go_live(pid), do: send(pid, :go_live)

  def status(pid) do
    GenServer.call(pid, :status, 2_000)
  catch
    :exit, _ -> :dead
  end

  @doc "Whether the connection delivers events: its shard count is the live one."
  def live?(%__MODULE__{bot: bot, shard_count: count}),
    do: Lingo.Instance.get(bot, :shard_count, nil) in [nil, count]

  @doc "Joins the shard's group once it is live, so other nodes can reach it."
  def maybe_join(%__MODULE__{joined: false} = state) do
    if live?(state) do
      Groups.join_shard(state.bot, state.shard_id, state.shard_count)
      %{state | joined: true}
    else
      state
    end
  end

  def maybe_join(state), do: state

  @impl true
  def init(opts) do
    bot = Keyword.fetch!(opts, :bot)
    Lingo.Instance.put_current(bot)
    Lingo.Cache.Cluster.local_only()

    state = %__MODULE__{
      bot: bot,
      shard_id: Keyword.fetch!(opts, :shard_id),
      shard_count: Keyword.fetch!(opts, :shard_count),
      token: Keyword.fetch!(opts, :token),
      intents: Keyword.fetch!(opts, :intents),
      gateway_url: Keyword.get(opts, :gateway_url),
      presence: Keyword.get(opts, :presence, []),
      encoding: Keyword.get(opts, :encoding, :json),
      compression: Keyword.get(opts, :compression, :zlib)
    }

    send(self(), :connect)
    {:ok, state |> restore_session() |> maybe_join()}
  end

  # a session left by an earlier run of this shard resumes
  defp restore_session(state) do
    case Sessions.fetch(state.bot, state.shard_id, state.shard_count) do
      {session_id, url, seq} ->
        %{state | session_id: session_id, resume_gateway_url: url, seq: seq}

      nil ->
        state
    end
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state.state, state}

  @impl true
  def handle_cast({:send, payload}, state), do: {:noreply, Transport.enqueue(state, payload)}

  def handle_cast({:update_presence, presence}, state) do
    status = presence[:status] || :online
    payload = Payload.presence_update(status, presence[:text], presence[:activity])
    {:noreply, Transport.enqueue(%{state | presence: presence}, payload)}
  end

  @impl true
  def handle_info(:connect, %{ws: nil, connect_task: nil} = state),
    do: {:noreply, Transport.start_connect(%{state | connect_timer: nil})}

  def handle_info(:connect, state), do: {:noreply, %{state | connect_timer: nil}}

  def handle_info(:reconnect, state), do: {:noreply, Transport.reconnect(state)}

  def handle_info(:go_live, state), do: {:noreply, maybe_join(state)}

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
    Transport.send_frame(state, Payload.heartbeat(state.seq))
    {:noreply, state}
  end

  def handle_info(:identify, %{ws: %WebSocket{}} = state),
    do: {:noreply, Protocol.identify(%{state | identify_timer: nil})}

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
      {:error, _ws, _reason} -> {:noreply, Protocol.dropped(state)}
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

  defp handle_frame({:binary, data}, %{inflate: nil} = state), do: handle_data(data, state)

  defp handle_frame({:binary, data}, state) do
    case inflate(state.inflate, data) do
      {:ok, inflate, nil} -> {:noreply, %{state | inflate: inflate}}
      {:ok, inflate, data} -> handle_data(data, %{state | inflate: inflate})
      :error -> {:noreply, Transport.reconnect(state)}
    end
  end

  defp handle_frame({:text, data}, state), do: handle_data(data, state)
  defp handle_frame({:close, code, _reason}, state), do: Protocol.close(state, code)

  defp inflate(inflate, data) do
    {inflate, data} = Compression.push(inflate, data)
    {:ok, inflate, data}
  rescue
    ErlangError -> :error
  end

  defp handle_data(data, state) do
    case Codec.decode(data, state.encoding) do
      {:ok, payload} -> Protocol.handle(payload, state)
      :error -> {:noreply, state}
    end
  end
end
