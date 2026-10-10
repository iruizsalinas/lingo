defmodule Lingo.Type.AccessTokenTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.AccessToken

  @now ~U[2026-10-10 12:00:00Z]

  test "expires_at counts from when Discord answered" do
    token =
      AccessToken.new(
        %{
          "access_token" => "at",
          "token_type" => "Bearer",
          "refresh_token" => "rt",
          "expires_in" => 3600,
          "scope" => "identify guilds.join"
        },
        @now
      )

    assert %AccessToken{
             access_token: "at",
             refresh_token: "rt",
             scopes: ["identify", "guilds.join"],
             expires_at: ~U[2026-10-10 13:00:00Z]
           } = token
  end

  test "expired? with a margin" do
    past = %AccessToken{expires_at: DateTime.add(DateTime.utc_now(), -1, :second)}
    soon = %AccessToken{expires_at: DateTime.add(DateTime.utc_now(), 30, :second)}

    assert AccessToken.expired?(past)
    refute AccessToken.expired?(soon)
    assert AccessToken.expired?(soon, 60_000)
  end
end
