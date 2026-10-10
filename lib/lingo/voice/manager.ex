defmodule Lingo.Voice.Manager do
  @moduledoc false

  # Runs one Lingo.Voice.Connection per guild for the bot. A voice connection
  # needs two events from the main gateway for our own user: VOICE_STATE_UPDATE
  # (the session id) and VOICE_SERVER_UPDATE (token and endpoint). They can
  # arrive in either order, and arrive again when the bot moves or the voice
  # server changes, which restarts the connection.

  use GenServer

  alias Lingo.Voice.Connection

  require Logger

  @join_timeout 20_000

  def start_link(opts) do
    bot = Keyword.fetch!(opts, :bot)
    GenServer.start_link(__MODULE__, bot, name: Lingo.Instance.process_name(bot, __MODULE__))
  end

  defp server, do: Lingo.Instance.process_name(__MODULE__)

  @spec join(String.t(), String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def join(guild_id, channel_id, opts \\ []) do
    GenServer.call(
      server(),
      {:join, to_string(guild_id), to_string(channel_id), opts},
      :infinity
    )
  end

  @spec leave(String.t()) :: :ok
  def leave(guild_id), do: GenServer.call(server(), {:leave, to_string(guild_id)})

  @spec connection(String.t()) :: pid() | nil
  def connection(guild_id), do: GenServer.call(server(), {:connection, to_string(guild_id)})

  @doc "Called by the dispatcher for every voice event; a no-op when voice isn't running."
  @spec dispatch(atom(), map()) :: :ok
  def dispatch(event, data) when event in [:voice_state_update, :voice_server_update],
    do: GenServer.cast(server(), {event, data})

  def dispatch(_event, _data), do: :ok

  ## Server

  @impl true
  def init(bot) do
    Lingo.Instance.put_current(bot)
    {:ok, %{}}
  end

  @impl true
  def handle_call({:join, guild_id, channel_id, opts}, from, guilds) do
    guild = Map.get(guilds, guild_id, %{})

    if guild[:ready] == true and guild[:channel_id] == channel_id do
      {:reply, {:ok, guild.connection}, guilds}
    else
      send_voice_state(guild_id, channel_id, opts)

      Process.send_after(
        self(),
        {:join_timeout, guild_id, from},
        Keyword.get(opts, :timeout, @join_timeout)
      )

      guild =
        guild |> Map.update(:waiters, [from], &[from | &1]) |> Map.put(:channel_id, channel_id)

      {:noreply, Map.put(guilds, guild_id, guild)}
    end
  end

  def handle_call({:leave, guild_id}, _from, guilds) do
    send_voice_state(guild_id, nil, [])
    {guild, guilds} = Map.pop(guilds, guild_id)
    if guild, do: stop_connection(guild)
    {:reply, :ok, guilds}
  end

  def handle_call({:connection, guild_id}, _from, guilds),
    do: {:reply, get_in(guilds, [guild_id, :connection]), guilds}

  @impl true
  def handle_cast({:voice_state_update, %{"user_id" => user_id} = data}, guilds) do
    if user_id == Lingo.Instance.get(:user_id),
      do: {:noreply, own_voice_state(guilds, data)},
      else: {:noreply, guilds}
  end

  def handle_cast({:voice_server_update, %{"guild_id" => guild_id} = data}, guilds) do
    guild =
      guilds
      |> Map.get(guild_id, %{})
      |> Map.merge(%{token: data["token"], endpoint: data["endpoint"]})

    {:noreply, Map.put(guilds, guild_id, maybe_connect(guild_id, guild))}
  end

  def handle_cast(_message, guilds), do: {:noreply, guilds}

  # we left or were disconnected from voice
  defp own_voice_state(guilds, %{"guild_id" => guild_id, "channel_id" => nil}) do
    {guild, guilds} = Map.pop(guilds, guild_id)
    if guild, do: stop_connection(guild)
    guilds
  end

  defp own_voice_state(guilds, %{"guild_id" => guild_id} = data) do
    guild =
      guilds
      |> Map.get(guild_id, %{})
      |> Map.merge(%{session_id: data["session_id"], channel_id: data["channel_id"]})

    Map.put(guilds, guild_id, maybe_connect(guild_id, guild))
  end

  # starts a connection once both halves are known, replacing a stale one
  defp maybe_connect(
         guild_id,
         %{session_id: session_id, token: token, endpoint: endpoint} = guild
       )
       when is_binary(session_id) and is_binary(token) and is_binary(endpoint) do
    key = {session_id, token, endpoint, guild.channel_id}

    if guild[:key] == key and guild[:connection] do
      guild
    else
      stop_connection(guild)

      opts = [
        guild_id: guild_id,
        channel_id: guild.channel_id,
        user_id: Lingo.Instance.get(:user_id),
        session_id: session_id,
        token: token,
        endpoint: endpoint,
        subscriber: self()
      ]

      supervisor = Lingo.Instance.process_name(Lingo.Voice.Supervisor)

      case DynamicSupervisor.start_child(supervisor, {Connection, opts}) do
        {:ok, pid} ->
          Process.monitor(pid)
          Map.merge(guild, %{connection: pid, key: key, ready: false})

        {:error, reason} ->
          Logger.error(
            "Lingo voice #{guild_id}: could not start a connection: #{inspect(reason)}"
          )

          guild
      end
    end
  end

  defp maybe_connect(_guild_id, guild), do: guild

  defp stop_connection(%{connection: pid}) when is_pid(pid) do
    if Process.alive?(pid), do: Connection.disconnect(pid)
  catch
    :exit, _reason -> :ok
  end

  defp stop_connection(_guild), do: :ok

  defp send_voice_state(guild_id, channel_id, opts) do
    payload = Lingo.Gateway.Payload.voice_state_update(guild_id, channel_id, opts)
    Lingo.Gateway.ShardManager.send_to_guild_shard(guild_id, payload)
  end

  @impl true
  def handle_info({:lingo_voice, guild_id, :ready}, guilds) do
    guild_id = to_string(guild_id)

    case guilds do
      %{^guild_id => %{connection: pid, waiters: waiters} = guild} ->
        Enum.each(waiters, &GenServer.reply(&1, {:ok, pid}))
        {:noreply, Map.put(guilds, guild_id, %{guild | waiters: [], ready: true})}

      %{^guild_id => guild} ->
        {:noreply, Map.put(guilds, guild_id, Map.put(guild, :ready, true))}

      _unknown ->
        {:noreply, guilds}
    end
  end

  def handle_info({:join_timeout, guild_id, from}, guilds) do
    case guilds do
      %{^guild_id => %{waiters: waiters} = guild} ->
        if from in waiters, do: GenServer.reply(from, {:error, :timeout})
        {:noreply, Map.put(guilds, guild_id, %{guild | waiters: List.delete(waiters, from)})}

      _gone ->
        {:noreply, guilds}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, guilds) do
    guilds =
      Map.new(guilds, fn
        {guild_id, %{connection: ^pid} = guild} ->
          {guild_id, %{guild | connection: nil, ready: false}}

        entry ->
          entry
      end)

    {:noreply, guilds}
  end

  def handle_info(_message, guilds), do: {:noreply, guilds}
end
