defmodule Lingo.Rest.HTTP do
  @moduledoc false

  # A thin transport over OTP's :httpc. It moves bytes and nothing else:
  # encoding, decoding, retries and rate limiting belong to the caller.

  @type method :: :get | :post | :put | :patch | :delete
  @type headers :: [{String.t(), String.t()}]
  @type body :: {content_type :: String.t(), iodata()} | nil
  @type response :: %{status: pos_integer(), headers: headers(), body: binary()}

  @connect_timeout 10_000
  @timeout 30_000

  @spec request(method(), String.t(), headers(), body()) :: {:ok, response()} | {:error, term()}
  def request(method, url, headers, body \\ nil) do
    http_options = [
      connect_timeout: @connect_timeout,
      timeout: @timeout,
      autoredirect: false,
      ssl: Lingo.TLS.client_options()
    ]

    case :httpc.request(method, build_request(method, url, headers, body), http_options,
           body_format: :binary
         ) do
      {:ok, {{_version, status, _reason}, headers, body}} ->
        {:ok, %{status: status, headers: normalize_headers(headers), body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # :httpc wants the four element form for methods that may carry a body,
  # even when the body is empty
  defp build_request(method, url, headers, nil) when method in [:post, :put, :patch] do
    build_request(method, url, headers, {"", ""})
  end

  defp build_request(_method, url, headers, nil) do
    {String.to_charlist(url), encode_headers(headers)}
  end

  defp build_request(_method, url, headers, {content_type, body}) do
    {String.to_charlist(url), encode_headers(headers), String.to_charlist(content_type),
     IO.iodata_to_binary(body)}
  end

  defp encode_headers(headers) do
    for {name, value} <- headers, do: {String.to_charlist(name), String.to_charlist(value)}
  end

  defp normalize_headers(headers) do
    for {name, value} <- headers, do: {List.to_string(name), List.to_string(value)}
  end
end
