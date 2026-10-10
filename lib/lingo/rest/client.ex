defmodule Lingo.Rest.Client do
  @moduledoc false

  import Bitwise

  alias Lingo.Rest.{Deadline, Request, Route}

  @max_retries 3
  @max_rate_limit_retries 5

  @spec request(atom(), String.t(), keyword()) :: :ok | {:ok, any()} | {:error, any()}
  def request(method, path, opts \\ []) do
    opts = keyword_body(opts)
    snapshot = Lingo.Cache.Rest.begin(method, path, opts)

    result =
      if Request.interaction_callback?(path) do
        Request.once(method, path, opts)
      else
        do_api_request(
          method,
          path,
          opts,
          %{errors: 0, rate_limits: 0, last: nil},
          Deadline.new()
        )
      end

    Lingo.Cache.Rest.finish(snapshot, result)
  end

  # bodies may be keyword lists; lists of maps (positions, bulk overwrites) stay lists
  defp keyword_body(opts) do
    case opts[:json] do
      [{key, _} | _] = json when is_atom(key) -> Keyword.put(opts, :json, Map.new(json))
      _ -> opts
    end
  end

  defdelegate with_max_wait(max_wait, fun), to: Deadline

  # One request at a time per bucket. 429 and 5xx retries are capped separately,
  # and no single wait may run past the caller's deadline.
  defp do_api_request(_method, _path, _opts, %{errors: errors, last: last}, _deadline)
       when errors >= @max_retries do
    case last do
      {:status, status} -> {:error, %Lingo.Error{reason: :server_error, status: status}}
      {:transport, reason} -> {:error, %Lingo.Error{reason: :transport, details: reason}}
    end
  end

  defp do_api_request(method, path, opts, attempts, deadline) do
    route_key = Route.key(method, path, opts)
    known_wait = Lingo.Rest.Buckets.wait_time(route_key)

    if Deadline.past?(known_wait, deadline) do
      rate_limited(known_wait)
    else
      locked_request(method, path, opts, route_key, attempts, deadline)
    end
  end

  defp locked_request(method, path, opts, route_key, attempts, deadline) do
    # never time out before the limiter has a chance to answer an uncontended acquire
    acquire_timeout =
      case Deadline.remaining(deadline) do
        :infinity -> :infinity
        ms -> max(ms, 100)
      end

    case Lingo.Rest.RateLimiter.acquire(route_key, acquire_timeout) do
      {:ok, bucket_key} ->
        try do
          with :ok <- Lingo.Rest.Buckets.wait(route_key, deadline),
               :ok <- Lingo.Rest.GlobalLimit.wait(deadline) do
            send_request(method, path, opts, route_key, attempts, deadline)
          else
            {:error, {:rate_limited, ms}} -> rate_limited(ms)
          end
        after
          Lingo.Rest.RateLimiter.release(bucket_key)
        end
        |> case do
          {:retry, attempts} -> do_api_request(method, path, opts, attempts, deadline)
          result -> result
        end

      :timeout ->
        rate_limited(Lingo.Rest.Buckets.wait_time(route_key))
    end
  end

  defp send_request(method, path, opts, route_key, attempts, deadline) do
    case Request.send(method, path, opts) do
      {:ok, status, body, resp_headers} ->
        Lingo.Rest.Buckets.update(route_key, resp_headers)
        handle_status(method, path, opts, status, body, resp_headers, attempts, deadline)

      {:error, reason} ->
        backoff = 1_000 * (1 <<< attempts.errors)
        Process.sleep(backoff)
        {:retry, %{attempts | errors: attempts.errors + 1, last: {:transport, reason}}}
    end
  end

  defp handle_status(_method, _path, _opts, status, body, _headers, _attempts, _deadline)
       when status in 200..299 do
    Request.result(body)
  end

  defp handle_status(method, path, _opts, 429, body, headers, attempts, deadline) do
    global = match?(%{"global" => true}, body)
    retry_after = Request.retry_after(body, headers)

    notify_rate_limit(method, path, retry_after, global)

    if global, do: Lingo.Rest.GlobalLimit.pause(retry_after)

    # every 429 counts toward Discord's invalid request limit, so don't retry forever
    if attempts.rate_limits >= @max_rate_limit_retries or Deadline.past?(retry_after, deadline) do
      rate_limited(retry_after)
    else
      Process.sleep(retry_after)
      {:retry, %{attempts | rate_limits: attempts.rate_limits + 1}}
    end
  end

  defp handle_status(_method, _path, _opts, status, _body, _headers, attempts, _deadline)
       when status >= 500 do
    backoff = 1_000 * (1 <<< attempts.errors)
    Process.sleep(backoff)
    {:retry, %{attempts | errors: attempts.errors + 1, last: {:status, status}}}
  end

  defp handle_status(_method, _path, _opts, status, body, _headers, _attempts, _deadline) do
    {:error, Lingo.Error.from_response(status, body)}
  end

  defp rate_limited(ms), do: {:error, %Lingo.Error{reason: :rate_limited, retry_after: ms}}

  defp notify_rate_limit(method, path, retry_after, global) do
    Lingo.Bot.Runner.event(:rate_limit, %{
      method: method,
      path: path,
      retry_after: retry_after,
      global: global
    })
  end

  @doc "Parses a successful response with `fun`, each element of a list one."
  @spec into(:ok | {:ok, term()} | {:error, term()}, (map() -> term())) ::
          :ok | {:ok, term()} | {:error, term()}
  def into({:ok, data}, fun) when is_list(data), do: {:ok, Enum.map(data, fun)}
  def into({:ok, data}, fun), do: {:ok, fun.(data)}
  def into(other, _fun), do: other

  @doc "Query parameters from a function's options, without `:reason`."
  @spec params(keyword()) :: map()
  def params(opts), do: opts |> Keyword.drop([:reason]) |> Map.new()

  @doc "Calls `fun` with the application id, for application-scoped endpoints."
  @spec app((String.t() -> result)) :: result | {:error, Lingo.Error.t()} when result: term()
  def app(fun) do
    with {:ok, application_id} <- Lingo.Instance.application_id(), do: fun.(application_id)
  end
end
