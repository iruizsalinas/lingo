defmodule Lingo.OAuth2 do
  @moduledoc """
  OAuth2: sending users to authorize the app, trading the code for their
  token, and calling the API as them (their profile, guilds, connections and
  linked role data).

      url = Lingo.OAuth2.authorize_url(client_id: "123", scopes: ["identify", "role_connections.write"],
              redirect_uri: "https://example.com/callback", state: state)

      # on the redirect back
      {:ok, %{"access_token" => token}} =
        Lingo.OAuth2.exchange_code(code, "https://example.com/callback", client)

      {:ok, user} = Lingo.OAuth2.get_current_user(token)

  `client` is `[client_id: ..., client_secret: ...]`, from the Developer
  Portal. Token functions return Discord's token response: `"access_token"`,
  `"token_type"`, `"expires_in"` (seconds), `"refresh_token"` and `"scope"`.

  Calls made as a user are sent once, outside the bot's rate limit tracking
  (each token has its own limits); a 429 comes back as an error with its
  `retry_after`. They go to the current bot's API URL (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Request
  alias Lingo.Type.User

  @authorize "https://discord.com/oauth2/authorize"

  @type client :: [client_id: String.t(), client_secret: String.t()]
  @type token :: String.t()

  @doc """
  The URL to send a user to. Options: `:client_id` (required), `:scopes`
  (list), `:redirect_uri`, `:state` (check it when they come back),
  `:prompt` (`"consent"` or `"none"`), `:integration_type` (`0` guild, `1`
  user), and for adding a bot `:permissions` (a bitfield, see
  `Lingo.Permissions.from_list/1`), `:guild_id` and `:disable_guild_select`.

  With a `:redirect_uri` the URL asks for a code (`response_type=code`);
  without one it's a plain bot invite.
  """
  @spec authorize_url(keyword()) :: String.t()
  def authorize_url(opts) do
    params =
      [
        client_id: Keyword.fetch!(opts, :client_id),
        response_type: if(opts[:redirect_uri], do: "code"),
        scope: opts[:scopes] && Enum.join(opts[:scopes], " "),
        redirect_uri: opts[:redirect_uri],
        state: opts[:state],
        prompt: opts[:prompt],
        integration_type: opts[:integration_type],
        permissions: opts[:permissions],
        guild_id: opts[:guild_id],
        disable_guild_select: opts[:disable_guild_select]
      ]
      |> Enum.reject(fn {_key, value} -> value == nil end)

    @authorize <> "?" <> URI.encode_query(params, :rfc3986)
  end

  @doc "Trades the code a user came back with for their token."
  @spec exchange_code(String.t(), String.t(), client()) :: Api.result(map())
  def exchange_code(code, redirect_uri, client),
    do: token(client, grant_type: "authorization_code", code: code, redirect_uri: redirect_uri)

  @doc "Gets a fresh token with a refresh token."
  @spec refresh(token(), client()) :: Api.result(map())
  def refresh(refresh_token, client),
    do: token(client, grant_type: "refresh_token", refresh_token: refresh_token)

  @doc """
  A token for the app's owner, without a redirect: the client credentials
  grant. Team apps may only ask for `identify` and `applications.commands.update`.
  """
  @spec client_credentials([String.t()], client()) :: Api.result(map())
  def client_credentials(scopes, client),
    do: token(client, grant_type: "client_credentials", scope: Enum.join(scopes, " "))

  @doc """
  Revokes a token, and with it every token of that authorization.
  `hint` is `"access_token"` or `"refresh_token"`.
  """
  @spec revoke(token(), client(), String.t() | nil) :: Api.result()
  def revoke(token, client, hint \\ nil) do
    form = Enum.reject([token: token, token_type_hint: hint], &(elem(&1, 1) == nil))

    with {:ok, _body} <- post_form("/oauth2/token/revoke", client, form), do: :ok
  end

  @doc "The token's authorization: `\"application\"`, `\"scopes\"`, `\"expires\"` and, with `identify`, `\"user\"`."
  @spec get_authorization(token()) :: Api.result(map())
  def get_authorization(token), do: as_user(token, :get, "/oauth2/@me")

  @doc "The user who authorized (`identify` scope)."
  @spec get_current_user(token()) :: Api.result(User.t())
  def get_current_user(token) do
    with {:ok, user} <- as_user(token, :get, "/users/@me"), do: {:ok, User.new(user)}
  end

  @doc "The user's guilds (`guilds` scope). Options: `:before`, `:after`, `:limit`, `:with_counts`."
  @spec list_guilds(token(), keyword()) :: Api.result([map()])
  def list_guilds(token, opts \\ []),
    do: as_user(token, :get, "/users/@me/guilds", params: Map.new(opts))

  @doc "The user's connected accounts (`connections` scope)."
  @spec list_connections(token()) :: Api.result([map()])
  def list_connections(token), do: as_user(token, :get, "/users/@me/connections")

  @doc "The user's linked role data for an app (`role_connections.write` scope)."
  @spec get_role_connection(token(), Api.id()) :: Api.result(map())
  def get_role_connection(token, application_id),
    do: as_user(token, :get, "/users/@me/applications/#{application_id}/role-connection")

  @doc """
  Sets the user's linked role data for an app (`role_connections.write`
  scope): `:platform_name`, `:platform_username` and `:metadata`, keyed by
  the app's role connection metadata (see
  `Lingo.Api.Application.update_role_connection_metadata/1`).
  """
  @spec update_role_connection(token(), Api.id(), Api.params()) :: Api.result(map())
  def update_role_connection(token, application_id, params) do
    as_user(token, :put, "/users/@me/applications/#{application_id}/role-connection",
      json: Map.new(params)
    )
  end

  defp token(client, form), do: post_form("/oauth2/token", client, form)

  defp post_form(path, client, form) do
    auth = {:basic, Keyword.fetch!(client, :client_id), Keyword.fetch!(client, :client_secret)}
    once(:post, path, form: form, auth: auth)
  end

  defp as_user(token, method, path, opts \\ []),
    do: once(method, path, Keyword.put(opts, :auth, {:bearer, token}))

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
