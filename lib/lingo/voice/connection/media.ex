defmodule Lingo.Voice.Connection.Media do
  @moduledoc false

  # The UDP side of a voice connection: IP discovery, receiving and sending
  # audio, and starting playback once audio can go out. Every function takes
  # and returns the connection's state.

  import Bitwise

  alias Lingo.Voice.Connection
  alias Lingo.Voice.Connection.Signal
  alias Lingo.Voice.Dave.Session, as: Dave
  alias Lingo.Voice.{Opus, RTP}

  @discovery_attempts 5
  @keepalive_interval 5_000
  @max_unmapped_ssrcs 8
  @max_unmapped_packets 50

  def discover(%{status: :discovering} = state) do
    if state.discovery_attempts < @discovery_attempts do
      {ip, port} = state.remote
      :gen_udp.send(state.udp, ip, port, RTP.discovery_request(state.ssrc))
      Process.send_after(self(), :discover, 1_000)
      {:noreply, %{state | discovery_attempts: state.discovery_attempts + 1}}
    else
      {:stop, {:shutdown, :ip_discovery_failed}, state}
    end
  end

  def discover(state), do: {:noreply, state}

  # keeps the NAT mapping open while we only listen
  def keepalive(%{udp: udp, remote: {ip, port}} = state) do
    :gen_udp.send(udp, ip, port, <<state.keepalive::32-little, 0::32>>)
    schedule_keepalive()
    %{state | keepalive: state.keepalive + 1 &&& 0xFFFFFFFF}
  end

  def schedule_keepalive, do: Process.send_after(self(), :keepalive, @keepalive_interval)

  def receive_packet(packet, %{status: :discovering} = state) do
    case RTP.parse_discovery(packet) do
      {:ok, ip, port} ->
        Signal.send_json(state, 1, %{
          protocol: "udp",
          data: %{address: ip, port: port, mode: state.mode}
        })

        %{state | status: :selecting}

      :error ->
        state
    end
  end

  def receive_packet(packet, %{secret_key: key} = state) when key != nil do
    with true <- RTP.voice_packet?(packet),
         {:ok, header, opus} <- RTP.decrypt(state.mode, key, packet) do
      case Map.fetch(state.ssrc_users, header.ssrc) do
        {:ok, user_id} -> deliver(state, user_id, header, opus)
        :error -> hold_unmapped(state, header, opus)
      end
    else
      _not_audio -> state
    end
  end

  def receive_packet(_packet, state), do: state

  def deliver(state, user_id, header, opus) do
    case Dave.decrypt(state.dave, user_id, opus, Connection.now()) do
      {:ok, opus, dave} ->
        packet = %{opus: opus, sequence: header.sequence, timestamp: header.timestamp}
        Connection.notify(state, {:audio, user_id, packet})
        %{state | dave: dave}

      {:error, _reason, dave} ->
        %{state | dave: dave}
    end
  end

  def send_audio(%{secret_key: nil} = state, _opus), do: state

  def send_audio(state, opus) do
    case Dave.encrypt(state.dave, opus) do
      {:ok, frame, dave} ->
        state = set_speaking(%{state | dave: dave}, true)
        header = %{sequence: state.sequence, timestamp: state.timestamp, ssrc: state.ssrc}
        packet = RTP.encrypt(state.mode, state.secret_key, header, state.nonce, frame)
        {ip, port} = state.remote
        :gen_udp.send(state.udp, ip, port, packet)

        %{
          state
          | sequence: state.sequence + 1 &&& 0xFFFF,
            timestamp: state.timestamp + Opus.samples(opus) &&& 0xFFFFFFFF,
            nonce: state.nonce + 1 &&& 0xFFFFFFFF
        }

      # E2EE is on but our keys aren't ready yet: never send media unencrypted
      {:error, :not_ready} ->
        state
    end
  end

  def set_speaking(%{speaking?: speaking?} = state, speaking?), do: state
  def set_speaking(%{ssrc: nil} = state, _speaking?), do: state

  def set_speaking(state, speaking?) do
    Signal.send_json(state, 5, %{
      speaking: if(speaking?, do: 1, else: 0),
      delay: 0,
      ssrc: state.ssrc
    })

    %{state | speaking?: speaking?}
  end

  # kept until a Speaking message says whose they are; a second's worth per
  # SSRC, for a handful of SSRCs, so stray traffic can't pile up
  defp hold_unmapped(%{unmapped: unmapped} = state, header, opus) do
    if Map.has_key?(unmapped, header.ssrc) or map_size(unmapped) < @max_unmapped_ssrcs do
      held =
        Enum.take([{header, opus} | Map.get(unmapped, header.ssrc, [])], @max_unmapped_packets)

      %{state | unmapped: Map.put(unmapped, header.ssrc, held)}
    else
      state
    end
  end
end
