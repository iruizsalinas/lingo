defmodule Lingo.Rest.Buckets do
  @moduledoc false

  # Discord's per-route rate limit buckets, as the response headers describe
  # them, kept in the bot's ETS tables so callers check them without a process
  # hop. Deadlines are absolute system times in ms, or :infinity; waits that
  # would run past one return the remaining time instead of sleeping.

  alias Lingo.Rest.GlobalLimit

  @doc "Waits until the route's bucket has requests left."
  @spec wait(String.t(), integer() | :infinity) ::
          :ok | {:error, {:rate_limited, non_neg_integer()}}
  def wait(route_key, deadline \\ :infinity), do: wait_bucket(resolve(route_key), deadline)

  @doc "How long a request on this route would currently have to wait, in ms."
  @spec wait_time(String.t()) :: non_neg_integer()
  def wait_time(route_key) do
    now = System.system_time(:millisecond)
    bucket_key = resolve(route_key)

    bucket_wait =
      case lookup(bucket_key) do
        [{^bucket_key, remaining, reset_at, _limit}] when remaining <= 0 -> reset_at - now
        _ -> 0
      end

    max(max(bucket_wait, GlobalLimit.paused_until() - now), 0)
  end

  @doc "Records what a response's rate limit headers say about its bucket."
  @spec update(String.t(), [{String.t(), String.t()}] | %{String.t() => [String.t()]}) :: :ok
  def update(route_key, headers) do
    remaining = header(headers, "x-ratelimit-remaining")
    reset_after = header(headers, "x-ratelimit-reset-after")

    if (buckets = table(:buckets)) && remaining && reset_after do
      bucket_key =
        case header(headers, "x-ratelimit-bucket") do
          nil ->
            route_key

          hash ->
            bucket_key = "#{hash}:#{major(route_key)}"
            :ets.insert(table(:bucket_map), {route_key, bucket_key})
            bucket_key
        end

      reset_at = System.system_time(:millisecond) + trunc(number(reset_after, 0.0) * 1000)
      limit = number(header(headers, "x-ratelimit-limit"), 0)
      :ets.insert(buckets, {bucket_key, number(remaining, 0), reset_at, limit})
    end

    :ok
  end

  @doc "Drops buckets that reset over 30s ago, and the routes pointing at them."
  @spec cleanup() :: :ok
  def cleanup do
    with buckets when buckets != nil <- table(:buckets) do
      expired = System.system_time(:millisecond) - 30_000
      :ets.select_delete(buckets, [{{:_, :_, :"$1", :_}, [{:<, :"$1", expired}], [true]}])

      for {route_key, bucket_key} <- :ets.tab2list(table(:bucket_map)),
          :ets.lookup(buckets, bucket_key) == [],
          do: :ets.delete(table(:bucket_map), route_key)
    end

    :ok
  end

  @doc "The bucket a route belongs to, once Discord has said."
  @spec resolve(String.t()) :: String.t()
  def resolve(route_key) do
    case table(:bucket_map) && :ets.lookup(table(:bucket_map), route_key) do
      [{_, bucket_key}] -> bucket_key
      _ -> route_key
    end
  end

  @doc false
  def table(key) do
    case Lingo.Instance.get(:rate_limiter) do
      %{^key => table} -> table
      nil -> nil
    end
  end

  defp wait_bucket(bucket_key, deadline) do
    case lookup(bucket_key) do
      [{^bucket_key, remaining, reset_at, _limit} = bucket] when remaining <= 0 ->
        now = System.system_time(:millisecond)

        cond do
          reset_at <= now ->
            :ets.delete_object(table(:buckets), bucket)
            wait_bucket(bucket_key, deadline)

          deadline != :infinity and reset_at > deadline ->
            {:error, {:rate_limited, reset_at - now}}

          true ->
            Process.sleep(reset_at - now + 50)
            wait_bucket(bucket_key, deadline)
        end

      _ ->
        :ok
    end
  end

  defp lookup(bucket_key) do
    if buckets = table(:buckets), do: :ets.lookup(buckets, bucket_key), else: []
  end

  # buckets are shared per major parameter: channel, guild or webhook
  defp major(route_key) do
    case Regex.run(~r"webhooks/(\d+(?:/[^/:]+)?)|(?:channels|guilds)/(\d+)", route_key) do
      [_, webhook] -> webhook
      [_, "", id] -> id
      _ -> "global"
    end
  end

  defp header(headers, key) do
    value =
      Enum.find_value(headers, fn {name, value} -> if String.downcase(name) == key, do: value end)

    if is_list(value), do: List.first(value), else: value
  end

  defp number(nil, default), do: default

  defp number(string, default) do
    parse = if is_float(default), do: &Float.parse/1, else: &Integer.parse/1

    case parse.(string) do
      {number, _rest} -> number
      :error -> default
    end
  end
end
