defmodule Lingo.Api.Client do
  @moduledoc false

  import Bitwise

  @base_url "https://discord.com/api/v10"
  @user_agent "DiscordBot (https://github.com/iruizsalinas/lingo, 0.1.1)"
  @max_retries 3
  @discord_epoch 1_420_070_400_000

  @spec request(atom(), String.t(), keyword()) :: :ok | {:ok, any()} | {:error, any()}
  def request(method, path, opts \\ []) do
    if interaction_endpoint?(path) do
      do_interaction_request(method, path, opts)
    else
      do_api_request(method, path, opts, 0)
    end
  end

  # Interactions skip rate limiting and never retry.
  defp do_interaction_request(method, path, opts) do
    case fire_request(method, path, opts, retry: false) do
      {:ok, status, body, _headers} when status in 200..299 -> parse_body(body)
      {:ok, status, body, _headers} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  # One request at a time per bucket. 429s always retry, 5xx retries are capped.
  defp do_api_request(_method, _path, _opts, retries) when retries >= @max_retries do
    {:error, :max_retries}
  end

  defp do_api_request(method, path, opts, retries) do
    route_key = route_key(method, path, opts)
    bucket_key = Lingo.Api.RateLimiter.acquire(route_key)

    try do
      Lingo.Api.RateLimiter.wait(route_key)
      Lingo.Api.RateLimiter.wait_global()

      case fire_request(method, path, opts) do
        {:ok, status, body, resp_headers} ->
          Lingo.Api.RateLimiter.update(route_key, resp_headers)
          handle_status(method, path, opts, status, body, resp_headers, retries)

        {:error, _reason} ->
          backoff = 1_000 * (1 <<< retries)
          Process.sleep(backoff)
          {:retry, retries + 1}
      end
    after
      Lingo.Api.RateLimiter.release(bucket_key)
    end
    |> case do
      {:retry, new_retries} -> do_api_request(method, path, opts, new_retries)
      result -> result
    end
  end

  defp handle_status(_method, _path, _opts, status, body, _headers, _retries)
       when status in 200..299 do
    parse_body(body)
  end

  defp handle_status(method, path, _opts, 429, body, headers, _retries) do
    global = match?(%{"global" => true}, body)
    retry_after = extract_retry_after(body, headers)

    notify_rate_limit(method, path, retry_after, global)

    if global, do: Lingo.Api.RateLimiter.pause_global(retry_after)
    Process.sleep(retry_after)

    {:retry, 0}
  end

  defp handle_status(_method, _path, _opts, status, _body, _headers, retries)
       when status >= 500 do
    backoff = 1_000 * (1 <<< retries)
    Process.sleep(backoff)
    {:retry, retries + 1}
  end

  defp handle_status(_method, _path, _opts, status, body, _headers, _retries) do
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
      |> Keyword.merge(extra)

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

  # keep major params (channel_id, guild_id, webhook_id)
  defp generalize_path_segments(["webhooks", id, _token | rest]) do
    ["webhooks", id, ":token" | generalize_path_segments(rest)]
  end

  defp generalize_path_segments([resource, id | rest])
       when resource in ~w(channels guilds) do
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
    case Map.get(headers, key) do
      [value | _] -> value
      value when is_binary(value) -> value
      nil -> default
    end
  end

  def build_multipart(json, files) do
    payload_part = {"payload_json", Jason.encode!(json), [{"content-type", "application/json"}]}

    file_parts =
      files
      |> Enum.with_index()
      |> Enum.map(fn {{filename, data}, idx} ->
        {"files[#{idx}]", data,
         [{"content-disposition", "form-data; name=\"files[#{idx}]\"; filename=\"#{filename}\""}]}
      end)

    [payload_part | file_parts]
  end
end
