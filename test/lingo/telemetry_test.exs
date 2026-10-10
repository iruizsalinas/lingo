defmodule Lingo.TelemetryTest do
  use ExUnit.Case, async: true

  # Lingo doesn't depend on :telemetry, so in its own tests events go nowhere
  test "emitting without :telemetry is a no-op" do
    refute Code.ensure_loaded?(:telemetry)
    assert Lingo.Telemetry.execute([:shard, :ready], %{}, %{shard_id: 0}) == :ok
  end
end
