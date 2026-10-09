defmodule Lingo.Voice.Player do
  @moduledoc false

  # Feeds Opus packets to a voice connection in real time. Each packet is due
  # once the durations of the ones before it have elapsed, measured against
  # the monotonic clock, so timing never drifts however long playback runs.
  #
  # The clock starts with the first packet, and when the source falls behind
  # (ffmpeg starting up, a stream buffering) it restarts from the late packet
  # rather than bursting out everything that's overdue: receivers expect a
  # steady 20 ms beat, not a catch-up flood.

  alias Lingo.Voice.{Dave, Opus}

  @silence_frames 5
  # behind schedule by more than this, in microseconds, means the source stalled
  @max_lag 60_000

  @spec start_link(pid(), Enumerable.t()) :: {:ok, pid()}
  def start_link(connection, packets), do: {:ok, spawn_link(fn -> run(connection, packets) end)}

  defp run(connection, packets) do
    due = Enum.reduce(packets, nil, &send_at(connection, &1, &2))

    # silence after the last frame keeps receivers from interpolating into the next one
    Enum.reduce(
      List.duplicate(Dave.Frame.silence(), @silence_frames),
      due,
      &send_at(connection, &1, &2)
    )

    send(connection, {:player_done, self()})
  end

  defp send_at(connection, packet, due) do
    now = System.monotonic_time(:microsecond)

    due =
      cond do
        due == nil or now - due > @max_lag -> now
        true -> due
      end

    if due > now, do: Process.sleep(div(due - now, 1000))

    send(connection, {:player_frame, self(), packet})
    due + div(Opus.samples(packet) * 1_000_000, 48_000)
  end
end
