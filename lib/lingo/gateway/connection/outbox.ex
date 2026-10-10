defmodule Lingo.Gateway.Connection.Outbox do
  @moduledoc false

  # Payloads waiting to go out over the gateway. Discord allows 120 sends per
  # 60 seconds; we keep 5 in reserve for heartbeats, identify and resume,
  # which bypass the queue.

  @limit 115
  @window_ms 60_000

  defstruct queue: :queue.new(), count: 0, window_start: 0

  @type t :: %__MODULE__{
          queue: :queue.queue(iodata()),
          count: non_neg_integer(),
          window_start: integer()
        }

  @spec push(t(), iodata()) :: t()
  def push(%__MODULE__{} = outbox, data), do: %{outbox | queue: :queue.in(data, outbox.queue)}

  @doc """
  Takes the payloads that may be sent now, oldest first. When some must wait
  for the next window, also says how long, in ms.
  """
  @spec take(t(), integer()) :: {[iodata()], t(), non_neg_integer() | nil}
  def take(%__MODULE__{} = outbox, now) do
    outbox =
      if now - outbox.window_start >= @window_ms,
        do: %{outbox | count: 0, window_start: now},
        else: outbox

    take(outbox, now, [])
  end

  defp take(outbox, now, sent) do
    case :queue.out(outbox.queue) do
      {:empty, _} ->
        {Enum.reverse(sent), outbox, nil}

      {{:value, data}, rest} when outbox.count < @limit ->
        take(%{outbox | queue: rest, count: outbox.count + 1}, now, [data | sent])

      {{:value, _data}, _rest} ->
        {Enum.reverse(sent), outbox, max(outbox.window_start + @window_ms - now, 0)}
    end
  end
end
