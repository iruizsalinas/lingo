defmodule Lingo.Voice.Player do
  @moduledoc false

  # Feeds Opus packets to a voice connection in real time. Each packet is due
  # once the durations of the ones before it have elapsed, measured against
  # the monotonic clock, so timing never drifts however long playback runs.

  alias Lingo.Voice.{Dave, Opus}

  @silence_frames 5

  @spec start_link(pid(), Enumerable.t()) :: {:ok, pid()}
  def start_link(connection, packets), do: {:ok, spawn_link(fn -> run(connection, packets) end)}

  defp run(connection, packets) do
    start = System.monotonic_time(:microsecond)

    elapsed = Enum.reduce(packets, 0, &send_at(connection, &1, start, &2))

    # silence after the last frame keeps receivers from interpolating into the next one
    Enum.reduce(
      List.duplicate(Dave.Frame.silence(), @silence_frames),
      elapsed,
      &send_at(connection, &1, start, &2)
    )

    send(connection, {:player_done, self()})
  end

  defp send_at(connection, packet, start, elapsed) do
    delay = start + elapsed - System.monotonic_time(:microsecond)
    if delay > 0, do: Process.sleep(div(delay, 1000))

    send(connection, {:player_frame, self(), packet})
    elapsed + div(Opus.samples(packet) * 1_000_000, 48_000)
  end
end
