defmodule Lingo.Rest.GlobalLimit do
  @moduledoc false

  # The global rate limit: after a global 429 every request from the bot
  # waits until Discord's retry_after has passed.

  alias Lingo.Rest.Buckets

  @spec pause(non_neg_integer()) :: :ok
  def pause(ms) do
    if table = Buckets.table(:global) do
      resume_at = System.system_time(:millisecond) + ms
      extend_pause(table, resume_at)
    end

    :ok
  end

  defp extend_pause(table, resume_at) do
    case :ets.lookup(table, :paused_until) do
      [] ->
        unless :ets.insert_new(table, {:paused_until, resume_at}),
          do: extend_pause(table, resume_at)

      [{:paused_until, current}] when current >= resume_at ->
        :ok

      [{:paused_until, current}] ->
        spec = [{{:paused_until, current}, [], [{{:paused_until, resume_at}}]}]

        # Another pause, or expiry cleanup, can change the record in between.
        if :ets.select_replace(table, spec) == 0, do: extend_pause(table, resume_at)
    end
  end

  @doc "When the pause ends, in system ms; 0 when not paused."
  @spec paused_until() :: integer()
  def paused_until do
    with table when table != nil <- Buckets.table(:global),
         [{:paused_until, resume_at}] <- :ets.lookup(table, :paused_until) do
      resume_at
    else
      _ -> 0
    end
  end

  @spec wait(integer() | :infinity) :: :ok | {:error, {:rate_limited, non_neg_integer()}}
  def wait(deadline \\ :infinity) do
    case Buckets.table(:global) && :ets.lookup(Buckets.table(:global), :paused_until) do
      [{:paused_until, resume_at}] ->
        now = System.system_time(:millisecond)

        cond do
          resume_at <= now ->
            spec = [{{:paused_until, :"$1"}, [{:"=<", :"$1", now}], [true]}]
            :ets.select_delete(Buckets.table(:global), spec)
            wait(deadline)

          deadline != :infinity and resume_at > deadline ->
            {:error, {:rate_limited, resume_at - now}}

          true ->
            Process.sleep(resume_at - now + 10)
            wait(deadline)
        end

      _ ->
        :ok
    end
  end
end
