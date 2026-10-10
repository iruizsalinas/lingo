defmodule Lingo.Rest.Shared do
  @moduledoc false

  # Rate limit state shared with the other nodes running the bot, so one
  # node's exhausted bucket or global 429 holds the others back too instead
  # of each finding out with its own 429. Only exhaustion is shared (an
  # update per request would cost more than the 429s it saves), and each
  # node applies it against its own clock.

  alias Lingo.Gateway.Groups
  alias Lingo.Instance
  alias Lingo.Rest.{Buckets, GlobalLimit}

  @doc "Shares a response's bucket state when it has no requests left."
  @spec bucket(String.t(), list() | map()) :: :ok
  def bucket(route_key, headers) do
    if exhausted?(headers),
      do: Groups.cast_others(Instance.current(), Buckets, :update, [route_key, headers])

    :ok
  end

  @doc "Shares a global pause."
  @spec pause(non_neg_integer()) :: :ok
  def pause(ms), do: Groups.cast_others(Instance.current(), GlobalLimit, :pause, [ms])

  defp exhausted?(headers) do
    Enum.any?(headers, fn {name, value} ->
      String.downcase(to_string(name)) == "x-ratelimit-remaining" and
        to_string(List.wrap(value) |> List.first()) == "0"
    end)
  end
end
