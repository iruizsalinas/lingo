defmodule Lingo.Rest.GlobalLimitTest do
  use ExUnit.Case, async: true

  alias Lingo.Rest.{Buckets, GlobalLimit}

  test "concurrent pauses never shorten the longest requested deadline" do
    Lingo.TestBot.start(start: [:rate_limiter])
    table = Buckets.table(:global)

    for round <- 1..1_000 do
      if rem(round, 2) == 0,
        do: :ets.insert(table, {:paused_until, System.system_time(:millisecond) - 1}),
        else: :ets.delete(table, :paused_until)

      parent = self()

      cleanup =
        Task.async(fn ->
          send(parent, {:waiting, self()})

          receive do
            :go -> GlobalLimit.wait(0)
          end
        end)

      tasks =
        for index <- 1..32 do
          Task.async(fn ->
            send(parent, {:waiting, self()})

            receive do
              :go ->
                duration = index * 10_000
                deadline = System.system_time(:millisecond) + duration
                GlobalLimit.pause(duration)
                deadline
            end
          end)
        end

      for _ <- [cleanup | tasks], do: assert_receive({:waiting, _pid})
      Enum.each([cleanup | tasks], &send(&1.pid, :go))
      expected = tasks |> Enum.map(&Task.await/1) |> Enum.max()
      Task.await(cleanup)
      assert GlobalLimit.paused_until() >= expected, "a concurrent pause shortened round #{round}"
    end
  end
end
