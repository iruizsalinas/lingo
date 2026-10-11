defmodule Lingo.Api.InviteTest do
  use ExUnit.Case, async: true

  @base_url "https://discord.com/api/v10"
  @guild_id "123456789012345678"
  @user_id "234567890123456789"

  setup do
    %{bot: Lingo.TestBot.start(token: "test-bot-token", start: [:rate_limiter])}
  end

  defp capture(status, body \\ "") do
    test_pid = self()

    Lingo.Instance.put(Lingo.Instance.current(), :http_request, fn method,
                                                                   url,
                                                                   headers,
                                                                   request_body ->
      send(test_pid, {:request, method, url, headers, request_body})

      {:ok,
       %{
         status: status,
         headers: [{"content-type", "application/json"}],
         body: body
       }}
    end)
  end

  for {function, method} <- [
        {{Lingo.Api.Invite, :add_target_user}, :put},
        {{Lingo.Api.Invite, :remove_target_user}, :delete}
      ] do
    test "#{elem(function, 1)} uses the user route without a body and handles 204" do
      capture(204)

      assert :ok =
               apply(unquote(elem(function, 0)), unquote(elem(function, 1)), [
                 "test-invite",
                 @user_id
               ])

      assert_received {:request, unquote(method), url, headers, nil}
      assert url == @base_url <> "/invites/test-invite/target-users/#{@user_id}"
      assert {"authorization", "Bot test-bot-token"} in headers
    end
  end

  for {function, suffix} <- [
        {{Lingo.Api.Invite, :bulk_add_target_users}, "bulk-add"},
        {{Lingo.Api.Invite, :bulk_delete_target_users}, "bulk-delete"}
      ] do
    test "#{elem(function, 1)} sends a JSON user_ids array and handles 204" do
      capture(204)
      user_ids = [@user_id, "345678901234567890"]

      assert :ok =
               apply(unquote(elem(function, 0)), unquote(elem(function, 1)), [
                 "test-invite",
                 user_ids
               ])

      assert_received {:request, :post, url, headers, {"application/json", body}}
      assert url == @base_url <> "/invites/test-invite/target-users/" <> unquote(suffix)
      assert JSON.decode!(IO.iodata_to_binary(body)) == %{"user_ids" => user_ids}
      assert {"authorization", "Bot test-bot-token"} in headers
    end

    test "#{elem(function, 1)} sends the documented maximum in one request" do
      capture(204)
      user_ids = Enum.map(1..1000, &Integer.to_string(234_567_890_123_456_789 + &1))

      assert :ok =
               apply(unquote(elem(function, 0)), unquote(elem(function, 1)), [
                 "test-invite",
                 user_ids
               ])

      assert_received {:request, :post, _, _, {"application/json", body}}
      assert JSON.decode!(IO.iodata_to_binary(body)) == %{"user_ids" => user_ids}
      refute_received {:request, _, _, _, _}
    end
  end

  test "incident actions preserve explicit nulls and return the full incidents data" do
    params = %{
      invites_disabled_until: "2026-10-09T13:00:00Z",
      dms_disabled_until: nil
    }

    response = %{
      "invites_disabled_until" => params.invites_disabled_until,
      "dms_disabled_until" => nil,
      "dm_spam_detected_at" => "2026-10-09T11:00:00Z",
      "raid_detected_at" => "2026-10-09T11:30:00Z"
    }

    capture(200, JSON.encode!(response))

    assert {:ok,
            %Lingo.Type.IncidentsData{
              invites_disabled_until: ~U[2026-10-09 13:00:00Z],
              dms_disabled_until: nil,
              dm_spam_detected_at: ~U[2026-10-09 11:00:00Z],
              raid_detected_at: ~U[2026-10-09 11:30:00Z]
            }} = Lingo.Api.Guild.update_incident_actions(@guild_id, params)

    assert_received {:request, :put, url, headers, {"application/json", body}}
    assert url == @base_url <> "/guilds/#{@guild_id}/incident-actions"

    assert JSON.decode!(IO.iodata_to_binary(body)) == %{
             "invites_disabled_until" => params.invites_disabled_until,
             "dms_disabled_until" => nil
           }

    assert {"authorization", "Bot test-bot-token"} in headers
  end

  test "incident actions accept keywords and leave omitted fields out of the request" do
    capture(200, ~s({"dms_disabled_until":null}))

    assert {:ok, %Lingo.Type.IncidentsData{dms_disabled_until: nil}} =
             Lingo.Api.Guild.update_incident_actions(@guild_id, dms_disabled_until: nil)

    assert_received {:request, :put, _, _, {"application/json", body}}
    assert JSON.decode!(IO.iodata_to_binary(body)) == %{"dms_disabled_until" => nil}
  end

  test "incident actions accept string-keyed maps without changing timestamp offsets" do
    params = %{"invites_disabled_until" => "2026-10-09T14:00:00+02:00"}
    capture(200, JSON.encode!(params))

    assert {:ok, %Lingo.Type.IncidentsData{invites_disabled_until: ~U[2026-10-09 12:00:00Z]}} =
             Lingo.Api.Guild.update_incident_actions(@guild_id, params)

    assert_received {:request, :put, _, _, {"application/json", body}}
    assert JSON.decode!(IO.iodata_to_binary(body)) == params
  end

  for {function, args} <- [
        {{Lingo.Api.Invite, :add_target_user}, ["test-invite", @user_id]},
        {{Lingo.Api.Invite, :remove_target_user}, ["test-invite", @user_id]},
        {{Lingo.Api.Invite, :bulk_add_target_users}, ["test-invite", [@user_id]]},
        {{Lingo.Api.Invite, :bulk_delete_target_users}, ["test-invite", [@user_id]]},
        {{Lingo.Api.Guild, :update_incident_actions}, [@guild_id, %{dms_disabled_until: nil}]}
      ] do
    test "#{elem(function, 1)} propagates Discord permission errors" do
      error = %{"code" => 50_013, "message" => "Missing Permissions"}
      capture(403, JSON.encode!(error))

      assert {:error, %Lingo.Error{status: 403, details: ^error}} =
               apply(
                 unquote(elem(function, 0)),
                 unquote(elem(function, 1)),
                 unquote(Macro.escape(args))
               )

      assert_received {:request, _, _, _, _}
      refute_received {:request, _, _, _, _}
    end
  end

  test "bulk target user validation errors are returned without splitting or retrying" do
    user_ids = Enum.map(1..1001, &Integer.to_string(234_567_890_123_456_789 + &1))

    error = %{
      "code" => 50_035,
      "message" => "Invalid Form Body",
      "errors" => %{"user_ids" => %{}}
    }

    capture(400, JSON.encode!(error))

    assert {:error, %Lingo.Error{status: 400, details: ^error}} =
             Lingo.Api.Invite.bulk_add_target_users("test-invite", user_ids)

    assert_received {:request, :post, _, _, {"application/json", body}}
    assert JSON.decode!(IO.iodata_to_binary(body)) == %{"user_ids" => user_ids}
    refute_received {:request, _, _, _, _}
  end

  test "target users job status comes back parsed" do
    # Discord's example response
    capture(
      200,
      JSON.encode!(%{
        "status" => 3,
        "total_users" => 100,
        "processed_users" => 41,
        "created_at" => "2025-01-08T12:00:00.000000+00:00",
        "completed_at" => nil,
        "error_message" => "Failed to parse CSV file"
      })
    )

    assert {:ok,
            %{
              status: :failed,
              total_users: 100,
              processed_users: 41,
              created_at: ~U[2025-01-08 12:00:00.000000Z],
              completed_at: nil,
              error_message: "Failed to parse CSV file"
            }} = Lingo.Api.Invite.get_target_users_status("test-invite")

    assert_received {:request, :get, url, _, nil}
    assert url == @base_url <> "/invites/test-invite/target-users/job-status"
  end
end
