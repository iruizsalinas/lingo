defmodule Lingo.OAuth2 do
  @moduledoc """
  OAuth2: sending users to authorize the app, trading the code for their
  token, and calling the API as them (their profile, guilds, connections and
  linked role data).

      url = Lingo.OAuth2.authorize_url(client_id: "123", scopes: ["identify", "role_connections.write"],
              redirect_uri: "https://example.com/callback", state: state)

      # on the redirect back
      {:ok, token} = Lingo.OAuth2.exchange_code(code, "https://example.com/callback", client)
      {:ok, user} = Lingo.OAuth2.get_current_user(token)

  `client` is `[client_id: ..., client_secret: ...]`, from the Developer
  Portal. Token functions return a `Lingo.Type.AccessToken`; functions that
  call the API as the user take it, or its `access_token` string.

  Calls are sent once, outside the bot's rate limit tracking (each token has
  its own limits); a 429 comes back as an error with its `retry_after`. No
  bot needs to be running: calls go to the current bot's API URL when there
  is one (see `Lingo.with_bot/2`), and to Discord's otherwise.
  """

  alias Lingo.Api
  alias Lingo.OAuth2.HTTP
  alias Lingo.Type.{AccessToken, Connection, Guild, User}

  @authorize "https://discord.com/oauth2/authorize"

  @type client :: [client_id: String.t(), client_secret: String.t()]
  @type token :: AccessToken.t() | String.t()

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
  @spec exchange_code(String.t(), String.t(), client()) :: Api.result(AccessToken.t())
  def exchange_code(code, redirect_uri, client),
    do:
      HTTP.token(client, grant_type: "authorization_code", code: code, redirect_uri: redirect_uri)

  @doc "Gets a fresh token with a token's refresh token (or the refresh token itself)."
  @spec refresh(token(), client()) :: Api.result(AccessToken.t())
  def refresh(%AccessToken{refresh_token: refresh_token}, client),
    do: refresh(refresh_token, client)

  def refresh(refresh_token, client) when is_binary(refresh_token),
    do: HTTP.token(client, grant_type: "refresh_token", refresh_token: refresh_token)

  @doc """
  A token for the app's owner, without a redirect: the client credentials
  grant. Team apps may only ask for `identify` and `applications.commands.update`.
  """
  @spec client_credentials([String.t()], client()) :: Api.result(AccessToken.t())
  def client_credentials(scopes, client),
    do: HTTP.token(client, grant_type: "client_credentials", scope: Enum.join(scopes, " "))

  @doc """
  Revokes a token, and with it every token of that authorization. Give an
  `AccessToken`, or a token string with `hint` (`"access_token"` or
  `"refresh_token"`) saying which it is.
  """
  @spec revoke(token(), client(), String.t() | nil) :: Api.result()
  def revoke(token, client, hint \\ nil) do
    form =
      [token: HTTP.access_token(token), token_type_hint: hint || hint(token)]
      |> Enum.reject(&(elem(&1, 1) == nil))

    with {:ok, _body} <- HTTP.post_form("/oauth2/token/revoke", client, form), do: :ok
  end

  defp hint(%AccessToken{}), do: "access_token"
  defp hint(_token), do: nil

  @doc """
  The token's authorization: `:application` (Discord's application object),
  `:scopes`, `:expires` and, with the `identify` scope, `:user`.
  """
  @spec get_authorization(token()) ::
          Api.result(%{
            application: map(),
            scopes: [String.t()],
            expires: DateTime.t() | nil,
            user: User.t() | nil
          })
  def get_authorization(token) do
    with {:ok, data} <- HTTP.as_user(token, :get, "/oauth2/@me") do
      {:ok,
       %{
         application: data["application"],
         scopes: data["scopes"] || [],
         expires: Lingo.Type.Parse.timestamp(data["expires"]),
         user: User.new(data["user"])
       }}
    end
  end

  @doc "The user who authorized (`identify` scope)."
  @spec get_current_user(token()) :: Api.result(User.t())
  def get_current_user(token),
    do: HTTP.as_user(token, :get, "/users/@me") |> into(&User.new/1)

  @doc """
  The user's guilds (`guilds` scope), partial as in
  `Lingo.Api.User.list_guilds/1`. Options: `:before`, `:after`, `:limit`,
  `:with_counts`.
  """
  @spec list_guilds(token(), keyword()) :: Api.result([Guild.t()])
  def list_guilds(token, opts \\ []),
    do:
      HTTP.as_user(token, :get, "/users/@me/guilds", params: Map.new(opts)) |> into(&Guild.new/1)

  @doc "The user's connected accounts (`connections` scope)."
  @spec list_connections(token()) :: Api.result([Connection.t()])
  def list_connections(token),
    do: HTTP.as_user(token, :get, "/users/@me/connections") |> into(&Connection.new/1)

  @doc """
  The user's linked role data for an app (`role_connections.write` scope):
  `:platform_name`, `:platform_username` and `:metadata`.
  """
  @spec get_role_connection(token(), Api.id()) :: Api.result(role_connection())
  def get_role_connection(token, application_id) do
    HTTP.as_user(token, :get, "/users/@me/applications/#{application_id}/role-connection")
    |> into(&role_connection/1)
  end

  @doc """
  Sets the user's linked role data for an app (`role_connections.write`
  scope): `:platform_name`, `:platform_username` and `:metadata`, keyed by
  the app's role connection metadata (see
  `Lingo.Api.Application.update_role_connection_metadata/1`).
  """
  @spec update_role_connection(token(), Api.id(), Api.params()) :: Api.result(role_connection())
  def update_role_connection(token, application_id, params) do
    HTTP.as_user(token, :put, "/users/@me/applications/#{application_id}/role-connection",
      json: Map.new(params)
    )
    |> into(&role_connection/1)
  end

  @typedoc "A user's linked role data for an app."
  @type role_connection :: %{
          platform_name: String.t() | nil,
          platform_username: String.t() | nil,
          metadata: %{String.t() => String.t()}
        }

  defp role_connection(data) do
    %{
      platform_name: data["platform_name"],
      platform_username: data["platform_username"],
      metadata: data["metadata"] || %{}
    }
  end

  defp into({:ok, data}, fun) when is_list(data), do: {:ok, Enum.map(data, fun)}
  defp into({:ok, data}, fun), do: {:ok, fun.(data)}
  defp into(error, _fun), do: error
end
