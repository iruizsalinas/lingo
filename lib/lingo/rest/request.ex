defmodule Lingo.Rest.Request do
  @moduledoc false

  # Builds, sends and decodes a single HTTP request to Discord.

  @base_url "https://discord.com/api/v10"
  @user_agent "DiscordBot (https://github.com/iruizsalinas/lingo, #{Mix.Project.config()[:version]})"

  @doc "Sends one request, returning the status, decoded body and headers."
  @spec send(atom(), String.t(), keyword()) :: {:ok, integer(), term(), list()} | {:error, term()}
  def send(method, path, opts) do
    url = base_url() <> path <> query_string(opts[:params])

    case http_request().(method, url, build_headers(opts), encode_body(opts)) do
      {:ok, %{status: status, headers: headers, body: body}} ->
        {:ok, status, decode_body(body, headers), headers}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # a REST proxy may stand in for Discord, shared by every node and process
  defp base_url, do: bot_config(:rest_base_url) || @base_url

  # swappable so tests can stand in for Discord
  defp http_request, do: bot_config(:http_request) || (&Lingo.Rest.HTTP.request/4)

  # OAuth2 calls work without a bot (or with several and none picked): they
  # then go to Discord directly
  defp bot_config(key) do
    Lingo.Instance.get(key)
  rescue
    ArgumentError -> nil
  end

  defp query_string(params) when params in [nil, [], %{}], do: ""
  defp query_string(params), do: "?" <> URI.encode_query(params)

  defp encode_body(opts) do
    cond do
      parts = opts[:multipart] -> Lingo.Rest.Multipart.encode(parts)
      json = opts[:json] -> {"application/json", JSON.encode_to_iodata!(json)}
      form = opts[:form] -> {"application/x-www-form-urlencoded", URI.encode_query(form)}
      true -> nil
    end
  end

  defp decode_body(body, headers) do
    with "application/json" <> _ <- get_header(headers, "content-type", ""),
         {:ok, decoded} <- JSON.decode(body) do
      decoded
    else
      _ -> body
    end
  end

  defp build_headers(opts) do
    headers = [{"authorization", authorization(opts[:auth])}, {"user-agent", @user_agent}]
    reason = opts[:reason]
    if reason, do: [{"x-audit-log-reason", URI.encode(reason)} | headers], else: headers
  end

  # the bot's token, or an OAuth2 user's or app's credentials
  defp authorization(nil), do: "Bot #{Lingo.Instance.get(:token)}"
  defp authorization({:bearer, token}), do: "Bearer #{token}"

  defp authorization({:basic, client_id, client_secret}),
    do: "Basic " <> Base.encode64("#{client_id}:#{client_secret}")

  @doc "A response header, by lowercase name."
  @spec header(list(), String.t(), term()) :: term()
  def header(headers, key, default) do
    Enum.find_value(headers, default, fn {name, value} ->
      if String.downcase(name) == key, do: value
    end)
  end

  defp get_header(headers, key, default), do: header(headers, key, default)

  @doc "A successful response: `:ok` when Discord sent no body."
  @spec result(term()) :: :ok | {:ok, term()}
  def result(""), do: :ok
  def result(nil), do: :ok
  def result(body), do: {:ok, body}

  @doc "How long a 429 asks to wait, in ms."
  @spec retry_after(term(), list()) :: non_neg_integer()
  def retry_after(%{"retry_after" => seconds}, _headers), do: trunc(seconds * 1000)

  def retry_after(_body, headers) do
    case Float.parse(header(headers, "retry-after", "1")) do
      {seconds, _} -> trunc(seconds * 1000)
      :error -> 1000
    end
  end

  @doc "Interaction callbacks skip rate limiting and are never retried."
  @spec interaction_callback?(String.t()) :: boolean()
  def interaction_callback?(path),
    do: String.starts_with?(path, "/interactions/") and String.ends_with?(path, "/callback")

  @doc "Sends a request once, without rate limiting or retries."
  @spec once(atom(), String.t(), keyword()) :: :ok | {:ok, term()} | {:error, Lingo.Error.t()}
  def once(method, path, opts) do
    case __MODULE__.send(method, path, opts) do
      {:ok, status, body, _headers} when status in 200..299 -> result(body)
      {:ok, status, body, _headers} -> {:error, Lingo.Error.from_response(status, body)}
      {:error, reason} -> {:error, %Lingo.Error{reason: :transport, details: reason}}
    end
  end
end
