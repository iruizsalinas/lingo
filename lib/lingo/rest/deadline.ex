defmodule Lingo.Rest.Deadline do
  @moduledoc false

  # How long a call may wait on rate limits: the process's with_max_wait/2,
  # else the bot's :max_wait, else forever. Deadlines are absolute ms.

  @key :lingo_max_wait

  @spec with_max_wait(non_neg_integer() | :infinity, (-> result)) :: result when result: any()
  def with_max_wait(max_wait, fun) do
    previous = Process.put(@key, max_wait)

    try do
      fun.()
    after
      if previous == nil, do: Process.delete(@key), else: Process.put(@key, previous)
    end
  end

  @spec new() :: integer() | :infinity
  def new do
    case Process.get(@key) || Lingo.Instance.get(:max_wait) || :infinity do
      :infinity -> :infinity
      ms -> now() + ms
    end
  end

  @spec remaining(integer() | :infinity) :: non_neg_integer() | :infinity
  def remaining(:infinity), do: :infinity
  def remaining(deadline), do: max(deadline - now(), 0)

  @doc "Whether waiting `wait_ms` from now would run past the deadline."
  @spec past?(non_neg_integer(), integer() | :infinity) :: boolean()
  # max_wait limits rate limit waits, so an immediately available request
  # is allowed even if processing has already used up the budget.
  def past?(0, _deadline), do: false
  def past?(_wait_ms, :infinity), do: false
  def past?(wait_ms, deadline), do: now() + wait_ms > deadline

  defp now, do: System.system_time(:millisecond)
end
