defmodule Lingo.Gateway.Connection.OutboxTest do
  use ExUnit.Case, async: true

  alias Lingo.Gateway.Connection.Outbox

  test "the first send starts a full window regardless of the monotonic clock origin" do
    for now <- [-120_000, 1_000] do
      outbox = Enum.reduce(1..116, %Outbox{}, &Outbox.push(&2, {:text, to_string(&1)}))

      {frames, outbox, wait} = Outbox.take(outbox, now)
      assert length(frames) == 115
      assert wait == 60_000

      assert {[], ^outbox, 1} = Outbox.take(outbox, now + 59_999)
      assert {[{:text, "116"}], outbox, nil} = Outbox.take(outbox, now + 60_000)
      assert outbox.count == 1
    end
  end
end
