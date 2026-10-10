defmodule Lingo.OAuth2.HTTP do
  @moduledoc false

  # Requests made for Lingo.OAuth2: token requests with the app's client
  # credentials, and API calls as a user with their token. Each is sent once,
  # outside the bot's rate limit tracking (every token has its own limits).

  alias Lingo.Rest.Request
  alias Lingo.Type.AccessToken

  @spec token(keyword(), keyword()) :: {:ok, AccessToken.t()} | {:error, Lingo.Error.t()}
  def token(client, form) do
    with {:ok, body} <- post_form("/oauth2/token", client, form),
         do: {:ok, AccessToken.new(body)}
  end

  @spec post_form(String.t(), keyword(), keyword()) :: {:ok, term()} | {:error, Lingo.Error.t()}
  def post_form(path, client, form) do
    auth = {:basic, Keyword.fetch!(client, :client_id), Keyword.fetch!(client, :client_secret)}
    once(:post, path, form: form, auth: auth)
  end

  @spec as_user(String.t() | AccessToken.t(), atom(), String.t(), keyword()) ::
          {:ok, term()} | {:error, Lingo.Error.t()}
  def as_user(token, method, path, opts \\ []),
    do: once(method, path, Keyword.put(opts, :auth, {:bearer, access_token(token)}))

  @doc "The token string, from a string or an `AccessToken`."
  def access_token(%AccessToken{access_token: token}), do: token
  def access_token(token) when is_binary(token), do: token

  defp once(method, path, opts) do
    case Request.send(method, path, opts) do
      {:ok, status, body, _headers} when status in 200..299 -> {:ok, body}
      {:ok, 429, body, headers} -> {:error, rate_limited(body, headers)}
      {:ok, status, body, _headers} -> {:error, Lingo.Error.from_response(status, body)}
      {:error, reason} -> {:error, %Lingo.Error{reason: :transport, details: reason}}
    end
  end

  defp rate_limited(body, headers),
    do: %Lingo.Error{reason: :rate_limited, retry_after: Request.retry_after(body, headers)}
end
