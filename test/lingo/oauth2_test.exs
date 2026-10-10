defmodule Lingo.OAuth2Test do
  use ExUnit.Case, async: true

  alias Lingo.OAuth2
  alias Lingo.Type.{AccessToken, Connection, Guild}

  @client [client_id: "123", client_secret: "shh"]

  setup do
    Lingo.TestBot.start(token: "bot-token", start: [:rate_limiter])
    :ok
  end

  defp respond(status, body, headers \\ []) do
    test_pid = self()

    Lingo.Instance.put(Lingo.Instance.current(), :http_request, fn method,
                                                                   url,
                                                                   headers_sent,
                                                                   sent ->
      send(test_pid, {:request, method, url, Map.new(headers_sent), sent})
      headers = [{"content-type", "application/json"} | headers]
      {:ok, %{status: status, headers: headers, body: JSON.encode!(body)}}
    end)
  end

  describe "authorize_url/1" do
    test "asks for a code when there's a redirect" do
      url =
        OAuth2.authorize_url(
          client_id: "123",
          scopes: ["identify", "guilds.join"],
          redirect_uri: "https://example.com/cb?x=1",
          state: "abc",
          prompt: "none"
        )

      %URI{host: "discord.com", path: "/oauth2/authorize", query: query} = URI.parse(url)

      assert URI.decode_query(query) == %{
               "client_id" => "123",
               "response_type" => "code",
               "scope" => "identify guilds.join",
               "redirect_uri" => "https://example.com/cb?x=1",
               "state" => "abc",
               "prompt" => "none"
             }

      # scopes are separated by %20, as Discord documents
      assert query =~ "scope=identify%20guilds.join"
    end

    test "is a plain bot invite without a redirect" do
      url =
        OAuth2.authorize_url(
          client_id: "123",
          scopes: ["bot", "applications.commands"],
          permissions: 8,
          guild_id: "9",
          disable_guild_select: true
        )

      query = url |> URI.parse() |> Map.get(:query) |> URI.decode_query()
      refute Map.has_key?(query, "response_type")
      assert %{"permissions" => "8", "guild_id" => "9", "disable_guild_select" => "true"} = query
    end
  end

  describe "tokens" do
    test "exchanging a code posts a form with HTTP Basic client auth" do
      respond(200, %{
        "access_token" => "at",
        "token_type" => "Bearer",
        "refresh_token" => "rt",
        "expires_in" => 604_800,
        "scope" => "identify guilds"
      })

      before = DateTime.utc_now()

      assert {:ok,
              %AccessToken{
                access_token: "at",
                token_type: "Bearer",
                refresh_token: "rt",
                scopes: ["identify", "guilds"],
                expires_at: expires_at
              } = token} = OAuth2.exchange_code("the-code", "https://example.com/cb", @client)

      assert DateTime.diff(expires_at, before) in 604_799..604_801
      refute AccessToken.expired?(token)
      assert AccessToken.expired?(token, :timer.hours(24 * 8))

      assert_received {:request, :post, "https://discord.com/api/v10/oauth2/token", headers,
                       {"application/x-www-form-urlencoded", form}}

      assert headers["authorization"] == "Basic " <> Base.encode64("123:shh")

      assert URI.decode_query(form) == %{
               "grant_type" => "authorization_code",
               "code" => "the-code",
               "redirect_uri" => "https://example.com/cb"
             }
    end

    test "refresh, client credentials and revoke" do
      respond(200, %{"access_token" => "at2"})

      assert {:ok, _} = OAuth2.refresh("rt", @client)
      assert_received {:request, :post, _, _, {_, form}}
      assert URI.decode_query(form) == %{"grant_type" => "refresh_token", "refresh_token" => "rt"}

      assert {:ok, _} =
               OAuth2.client_credentials(["identify", "applications.commands.update"], @client)

      assert_received {:request, :post, _, _, {_, form}}

      assert %{
               "grant_type" => "client_credentials",
               "scope" => "identify applications.commands.update"
             } =
               URI.decode_query(form)

      assert :ok = OAuth2.revoke("at", @client, "access_token")

      assert_received {:request, :post, "https://discord.com/api/v10/oauth2/token/revoke", _,
                       {_, form}}

      assert URI.decode_query(form) == %{"token" => "at", "token_type_hint" => "access_token"}
    end

    test "take the token struct where a token string goes" do
      respond(200, %{"access_token" => "at2"})
      token = %AccessToken{access_token: "at", refresh_token: "rt"}

      assert {:ok, %AccessToken{access_token: "at2"}} = OAuth2.refresh(token, @client)
      assert_received {:request, :post, _, _, {_, form}}
      assert URI.decode_query(form)["refresh_token"] == "rt"

      # the hint comes from the struct
      assert :ok = OAuth2.revoke(token, @client)
      assert_received {:request, :post, _, _, {_, form}}
      assert URI.decode_query(form) == %{"token" => "at", "token_type_hint" => "access_token"}
    end

    test "a token without expires_in never expires" do
      token = AccessToken.new(%{"access_token" => "at"})
      assert token.expires_at == nil
      refute AccessToken.expired?(token)
    end

    test "errors and rate limits come back as Lingo.Error" do
      respond(400, %{"error" => "invalid_grant"})

      assert {:error, %Lingo.Error{status: 400}} =
               OAuth2.exchange_code("bad", "https://x", @client)

      respond(429, %{"retry_after" => 2.5, "message" => "slow down"})

      assert {:error, %Lingo.Error{reason: :rate_limited, retry_after: 2_500}} =
               OAuth2.refresh("rt", @client)
    end
  end

  describe "as the user" do
    test "calls use the user's bearer token, not the bot's" do
      respond(200, %{"id" => "42", "username" => "someone"})

      assert {:ok, %Lingo.Type.User{id: "42"}} = OAuth2.get_current_user("user-token")
      assert_received {:request, :get, "https://discord.com/api/v10/users/@me", headers, nil}
      assert headers["authorization"] == "Bearer user-token"

      assert {:ok, _user} = OAuth2.get_current_user(%AccessToken{access_token: "from-struct"})
      assert_received {:request, :get, _, headers, nil}
      assert headers["authorization"] == "Bearer from-struct"
    end

    test "guilds, connections and the authorization come back parsed" do
      respond(200, [%{"id" => "9", "name" => "G", "permissions" => "8"}])
      assert {:ok, [%Guild{id: "9", permissions: "8"}]} = OAuth2.list_guilds("t")

      respond(200, [%{"id" => "1", "name" => "me", "type" => "github", "visibility" => 1}])

      assert {:ok, [%Connection{type: "github", name: "me", visibility: :everyone}]} =
               OAuth2.list_connections("t")

      respond(200, %{
        "application" => %{"id" => "200"},
        "scopes" => ["identify"],
        "expires" => "2026-10-17T00:00:00+00:00",
        "user" => %{"id" => "42"}
      })

      assert {:ok,
              %{
                application: %{"id" => "200"},
                scopes: ["identify"],
                expires: %DateTime{},
                user: %Lingo.Type.User{id: "42"}
              }} = OAuth2.get_authorization("t")
    end

    test "linked role data" do
      respond(200, %{"platform_name" => "Game"})

      assert {:ok, %{platform_name: "Game", platform_username: nil, metadata: %{}}} =
               OAuth2.update_role_connection("user-token", "200",
                 platform_name: "Game",
                 metadata: %{"level" => 10}
               )

      assert_received {:request, :put,
                       "https://discord.com/api/v10/users/@me/applications/200/role-connection",
                       _, {"application/json", body}}

      assert JSON.decode!(IO.iodata_to_binary(body)) == %{
               "platform_name" => "Game",
               "metadata" => %{"level" => 10}
             }
    end

    test "adding a user to a guild uses the bot's token and theirs" do
      respond(201, %{"user" => %{"id" => "42"}, "roles" => []})

      assert {:ok, %Lingo.Type.Member{}} =
               Lingo.Api.Member.create("9", "42", "user-token", nick: "hi")

      assert_received {:request, :put, "https://discord.com/api/v10/guilds/9/members/42", headers,
                       {"application/json", body}}

      assert headers["authorization"] == "Bot bot-token"

      assert JSON.decode!(IO.iodata_to_binary(body)) == %{
               "access_token" => "user-token",
               "nick" => "hi"
             }
    end
  end
end
