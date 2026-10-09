defmodule Lingo.Api.Client do
  @moduledoc false

  import Bitwise

  @base_url "https://discord.com/api/v10"
  @user_agent "DiscordBot (https://github.com/iruizsalinas/lingo, #{Mix.Project.config()[:version]})"
  @max_retries 3
  @max_rate_limit_retries 5
  @discord_epoch 1_420_070_400_000

  @spec request(atom(), String.t(), keyword()) :: :ok | {:ok, any()} | {:error, any()}
  def request(method, path, opts \\ []) do
    if interaction_endpoint?(path) do
      do_interaction_request(method, path, opts)
    else
      do_api_request(method, path, opts, %{errors: 0, rate_limits: 0}, deadline())
    end
  end

  @doc """
  Caps how long API calls made by `fun` will wait on rate limits, in ms.
  Calls that would wait longer return `{:error, {:rate_limited, retry_after_ms}}`.
  """
  @spec with_max_wait(non_neg_integer() | :infinity, (-> result)) :: result when result: any()
  def with_max_wait(max_wait, fun) do
    previous = Process.put(:lingo_max_wait, max_wait)

    try do
      fun.()
    after
      if previous == nil,
        do: Process.delete(:lingo_max_wait),
        else: Process.put(:lingo_max_wait, previous)
    end
  end

  defp deadline do
    case Process.get(:lingo_max_wait) || Lingo.Config.get(:max_wait) || :infinity do
      :infinity -> :infinity
      ms -> System.system_time(:millisecond) + ms
    end
  end

  defp remaining_ms(:infinity), do: :infinity
  defp remaining_ms(deadline), do: max(deadline - System.system_time(:millisecond), 0)

  defp past_deadline?(_wait_ms, :infinity), do: false

  defp past_deadline?(wait_ms, deadline),
    do: System.system_time(:millisecond) + wait_ms > deadline

  # Interactions skip rate limiting and never retry.
  defp do_interaction_request(method, path, opts) do
    case fire_request(method, path, opts) do
      {:ok, status, body, _headers} when status in 200..299 -> parse_body(body)
      {:ok, status, body, _headers} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  # One request at a time per bucket. 429 and 5xx retries are capped separately,
  # and no single wait may run past the caller's deadline.
  defp do_api_request(_method, _path, _opts, %{errors: errors}, _deadline)
       when errors >= @max_retries do
    {:error, :max_retries}
  end

  defp do_api_request(method, path, opts, attempts, deadline) do
    route_key = route_key(method, path, opts)
    known_wait = Lingo.Api.RateLimiter.wait_time(route_key)

    if past_deadline?(known_wait, deadline) do
      {:error, {:rate_limited, known_wait}}
    else
      locked_request(method, path, opts, route_key, attempts, deadline)
    end
  end

  defp locked_request(method, path, opts, route_key, attempts, deadline) do
    # never time out before the limiter has a chance to answer an uncontended acquire
    acquire_timeout =
      case remaining_ms(deadline) do
        :infinity -> :infinity
        ms -> max(ms, 100)
      end

    case Lingo.Api.RateLimiter.acquire(route_key, acquire_timeout) do
      {:ok, bucket_key} ->
        try do
          with :ok <- Lingo.Api.RateLimiter.wait(route_key, deadline),
               :ok <- Lingo.Api.RateLimiter.wait_global(deadline) do
            send_request(method, path, opts, route_key, attempts, deadline)
          end
        after
          Lingo.Api.RateLimiter.release(bucket_key)
        end
        |> case do
          {:retry, attempts} -> do_api_request(method, path, opts, attempts, deadline)
          result -> result
        end

      :timeout ->
        {:error, {:rate_limited, Lingo.Api.RateLimiter.wait_time(route_key)}}
    end
  end

  defp send_request(method, path, opts, route_key, attempts, deadline) do
    case fire_request(method, path, opts) do
      {:ok, status, body, resp_headers} ->
        Lingo.Api.RateLimiter.update(route_key, resp_headers)
        handle_status(method, path, opts, status, body, resp_headers, attempts, deadline)

      {:error, _reason} ->
        backoff = 1_000 * (1 <<< attempts.errors)
        Process.sleep(backoff)
        {:retry, %{attempts | errors: attempts.errors + 1}}
    end
  end

  defp handle_status(_method, _path, _opts, status, body, _headers, _attempts, _deadline)
       when status in 200..299 do
    parse_body(body)
  end

  defp handle_status(method, path, _opts, 429, body, headers, attempts, deadline) do
    global = match?(%{"global" => true}, body)
    retry_after = extract_retry_after(body, headers)

    notify_rate_limit(method, path, retry_after, global)

    if global, do: Lingo.Api.RateLimiter.pause_global(retry_after)

    # every 429 counts toward Discord's invalid request limit, so don't retry forever
    if attempts.rate_limits >= @max_rate_limit_retries or past_deadline?(retry_after, deadline) do
      {:error, {:rate_limited, retry_after}}
    else
      Process.sleep(retry_after)
      {:retry, %{attempts | rate_limits: attempts.rate_limits + 1}}
    end
  end

  defp handle_status(_method, _path, _opts, status, _body, _headers, attempts, _deadline)
       when status >= 500 do
    backoff = 1_000 * (1 <<< attempts.errors)
    Process.sleep(backoff)
    {:retry, %{attempts | errors: attempts.errors + 1}}
  end

  defp handle_status(_method, _path, _opts, status, body, _headers, _attempts, _deadline) do
    {:error, {status, body}}
  end

  defp fire_request(method, path, opts, extra \\ []) do
    headers = build_headers(opts[:reason])
    url = @base_url <> path

    req_opts =
      [method: method, url: url, headers: headers]
      |> maybe_put_json(opts[:json])
      |> maybe_put_params(opts[:params])
      |> maybe_put_multipart(opts[:multipart])
      # retries are handled here so they stay visible to the rate limiter
      |> Keyword.put(:retry, false)
      |> Keyword.merge(extra)
      |> Keyword.merge(Lingo.Config.get(:req_options) || [])

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, headers: resp_headers, body: body}} ->
        {:ok, status, body, resp_headers}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp notify_rate_limit(method, path, retry_after, global) do
    bot = Lingo.Config.bot_module()

    if bot && function_exported?(bot, :__handle_event__, 2) do
      bot.__handle_event__(:rate_limit, %{
        method: method,
        path: path,
        retry_after: retry_after,
        global: global
      })
    end
  end

  defp parse_body(""), do: :ok
  defp parse_body(nil), do: :ok
  defp parse_body(body), do: {:ok, body}

  defp extract_retry_after(body, headers) do
    case body do
      %{"retry_after" => seconds} -> trunc(seconds * 1000)
      _ -> parse_retry_after(get_header(headers, "retry-after", "1"))
    end
  end

  defp build_headers(reason) do
    headers = [
      {"authorization", "Bot #{Lingo.Config.token()}"},
      {"user-agent", @user_agent}
    ]

    if reason, do: [{"x-audit-log-reason", URI.encode(reason)} | headers], else: headers
  end

  defp maybe_put_json(opts, nil), do: opts
  defp maybe_put_json(opts, json), do: Keyword.put(opts, :json, json)

  defp maybe_put_params(opts, nil), do: opts
  defp maybe_put_params(opts, params), do: Keyword.put(opts, :params, params)

  defp maybe_put_multipart(opts, nil), do: opts

  defp maybe_put_multipart(opts, parts) do
    opts
    |> Keyword.delete(:json)
    |> Keyword.put(:form_multipart, parts)
  end

  # route key generation - matches discord.js bucket logic
  defp route_key(method, path, opts) do
    generalized =
      path
      |> String.split("/")
      |> generalize_path_segments()
      |> Enum.join("/")

    key = "#{method}:#{generalized}"

    # old message delete has a separate stricter bucket
    key = maybe_old_message_suffix(key, method, path)

    # channel name/topic edits have a sublimit
    maybe_channel_sublimit(key, method, path, opts)
  end

  defp generalize_path_segments([]), do: []

  # keep major params (channel_id, guild_id, webhook_id + webhook_token)
  defp generalize_path_segments(["webhooks", id, token | rest]) do
    if snowflake?(token) or token in ["messages"] do
      ["webhooks", id | generalize_path_segments([token | rest])]
    else
      ["webhooks", id, token | generalize_path_segments(rest)]
    end
  end

  defp generalize_path_segments([resource, id | rest])
       when resource in ~w(channels guilds webhooks) do
    [resource, id | generalize_path_segments(rest)]
  end

  # all reaction sub-routes share one bucket regardless of emoji
  defp generalize_path_segments(["reactions" | _rest]) do
    ["reactions", ":reaction"]
  end

  defp generalize_path_segments([segment | rest]) do
    if snowflake?(segment) do
      [":id" | generalize_path_segments(rest)]
    else
      [segment | generalize_path_segments(rest)]
    end
  end

  defp snowflake?(str) do
    case Integer.parse(str) do
      {n, ""} when n > 1_000_000 -> true
      _ -> false
    end
  end

  defp maybe_old_message_suffix(key, :delete, path) do
    case Regex.run(~r"/channels/\d+/messages/(\d+)$", path) do
      [_, message_id] ->
        ts = (String.to_integer(message_id) >>> 22) + @discord_epoch
        age_ms = System.system_time(:millisecond) - ts

        if age_ms > 14 * 24 * 60 * 60 * 1000 do
          key <> "/old"
        else
          key
        end

      _ ->
        key
    end
  end

  defp maybe_old_message_suffix(key, _method, _path), do: key

  defp maybe_channel_sublimit(key, :patch, path, opts) do
    if String.match?(path, ~r"^/channels/\d+$") do
      json = opts[:json]

      if is_map(json) and
           (Map.has_key?(json, :name) or Map.has_key?(json, :topic) or
              Map.has_key?(json, "name") or Map.has_key?(json, "topic")) do
        key <> "/name-topic"
      else
        key
      end
    else
      key
    end
  end

  defp maybe_channel_sublimit(key, _method, _path, _opts), do: key

  defp interaction_endpoint?(path) do
    String.starts_with?(path, "/interactions/") and String.ends_with?(path, "/callback")
  end

  defp parse_retry_after(str) do
    case Float.parse(str) do
      {f, _} -> trunc(f * 1000)
      :error -> 1000
    end
  end

  defp get_header(headers, key, default) do
    value =
      Map.get(headers, key) ||
        Enum.find_value(headers, fn {header, value} ->
          if String.downcase(header) == key, do: value
        end)

    case value do
      [value | _] -> value
      value when is_binary(value) -> value
      nil -> default
    end
  end

  def build_multipart(json, files) do
    payload_part = {"payload_json", {Jason.encode!(json), content_type: "application/json"}}

    file_parts =
      files
      |> Enum.with_index()
      |> Enum.map(fn {{filename, data}, idx} ->
        {"files[#{idx}]", {data, filename: filename}}
      end)

    [payload_part | file_parts]
  end
end
