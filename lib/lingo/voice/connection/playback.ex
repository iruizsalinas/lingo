defmodule Lingo.Voice.Connection.Playback do
  @moduledoc false

  # When a voice connection is ready, and starting and stopping its player.

  require Logger

  alias Lingo.Voice.{Connection, Player}
  alias Lingo.Voice.Connection.Media
  alias Lingo.Voice.Dave.Session, as: Dave

  def stop_player(%{player: nil} = state), do: state

  def stop_player(state) do
    Process.unlink(state.player)
    Process.exit(state.player, :kill)
    %{state | player: nil}
  end

  # ready once the transport is up; with DAVE on, media still waits for the
  # group keys, which a lone member never gets until someone else joins
  def check_ready(%{ready?: false, status: :connected} = state) do
    Connection.notify_ready(state)
    start_pending(%{state | ready?: true})
  end

  def check_ready(state), do: start_pending(state)

  # Playback starts once audio can actually go out, from its first packet:
  # nothing is lost to a connection still coming up, and a bot alone in an
  # end-to-end encrypted call starts playing when someone joins.
  def start_pending(%{pending: packets} = state) when packets != nil do
    if state.status == :connected and state.secret_key != nil and Dave.ready?(state.dave) do
      {:ok, player} = Player.start_link(self(), packets)
      %{state | player: player, pending: nil}
    else
      state
    end
  end

  def start_pending(state), do: state

  def playback(%{player: player}) when player != nil, do: :playing
  def playback(%{pending: pending}) when pending != nil, do: :waiting
  def playback(_state), do: :idle

  # the player ended: on its own, or because its source failed
  def finished(state, :normal) do
    Connection.notify(state, :playback_finished)
    Media.set_speaking(%{state | player: nil}, false)
  end

  def finished(state, reason) do
    reason =
      case reason do
        {exception, _stacktrace} when is_exception(exception) -> exception
        reason -> reason
      end

    Logger.error("Lingo voice #{state.guild_id}: playback failed: #{inspect(reason)}")
    Connection.notify(state, {:playback_failed, reason})
    Media.set_speaking(%{state | player: nil}, false)
  end
end
