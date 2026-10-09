defmodule Lingo.Api.ConventionalRestTest do
  use ExUnit.Case

  alias Lingo.Api.RateLimiter

  @base_url "https://discord.com/api/v10"
  @guild_id "123456789012345678"
  @user_id "234567890123456789"

  setup do
    if Process.whereis(RateLimiter) do
      for table <- [:lingo_rate_limits, :lingo_bucket_map, :lingo_global_rate_limit] do
        :ets.delete_all_objects(table)
      end
    else
      start_supervised!(RateLimiter)
    end

    previous =
      for key <- [:http_request, :token, :max_wait, :bot_module], do: {key, Lingo.Config.get(key)}

    Lingo.Config.put(:token, "test-bot-token")
    Lingo.Config.put(:max_wait, nil)
    Lingo.Config.put(:bot_module, nil)

    on_exit(fn -> Enum.each(previous, fn {key, value} -> Lingo.Config.put(key, value) end) end)

    :ok
  end

  defp capture(status, body \\ "") do
    test_pid = self()

    Lingo.Config.put(:http_request, fn method, url, headers, request_body ->
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
        {:add_invite_target_user, :put},
        {:remove_invite_target_user, :delete}
      ] do
    test "#{function} uses the user route without a body and handles 204" do
      capture(204)

      assert :ok = apply(Lingo, unquote(function), ["test-invite", @user_id])

      assert_received {:request, unquote(method), url, headers, nil}
      assert url == @base_url <> "/invites/test-invite/target-users/#{@user_id}"
      assert {"authorization", "Bot test-bot-token"} in headers
    end
  end

  for {function, suffix} <- [
        {:add_invite_target_users, "bulk-add"},
        {:remove_invite_target_users, "bulk-delete"}
      ] do
    test "#{function} sends a JSON user_ids array and handles 204" do
      capture(204)
      user_ids = [@user_id, "345678901234567890"]

      assert :ok = apply(Lingo, unquote(function), ["test-invite", user_ids])

      assert_received {:request, :post, url, headers, {"application/json", body}}
      assert url == @base_url <> "/invites/test-invite/target-users/" <> unquote(suffix)
      assert JSON.decode!(IO.iodata_to_binary(body)) == %{"user_ids" => user_ids}
      assert {"authorization", "Bot test-bot-token"} in headers
    end

    test "#{function} sends the documented maximum in one request" do
      capture(204)
      user_ids = Enum.map(1..1000, &Integer.to_string(234_567_890_123_456_789 + &1))

      assert :ok = apply(Lingo, unquote(function), ["test-invite", user_ids])
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

    assert {:ok, ^response} = Lingo.edit_guild_incident_actions(@guild_id, params)
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

    assert {:ok, %{"dms_disabled_until" => nil}} =
             Lingo.edit_guild_incident_actions(@guild_id, dms_disabled_until: nil)

    assert_received {:request, :put, _, _, {"application/json", body}}
    assert JSON.decode!(IO.iodata_to_binary(body)) == %{"dms_disabled_until" => nil}
  end

  test "incident actions accept string-keyed maps without changing timestamp offsets" do
    params = %{"invites_disabled_until" => "2026-10-09T14:00:00+02:00"}
    capture(200, JSON.encode!(params))

    assert {:ok, ^params} = Lingo.edit_guild_incident_actions(@guild_id, params)
    assert_received {:request, :put, _, _, {"application/json", body}}
    assert JSON.decode!(IO.iodata_to_binary(body)) == params
  end

  for {function, args} <- [
        {:add_invite_target_user, ["test-invite", @user_id]},
        {:remove_invite_target_user, ["test-invite", @user_id]},
        {:add_invite_target_users, ["test-invite", [@user_id]]},
        {:remove_invite_target_users, ["test-invite", [@user_id]]},
        {:edit_guild_incident_actions, [@guild_id, %{dms_disabled_until: nil}]}
      ] do
    test "#{function} propagates Discord permission errors" do
      error = %{"code" => 50_013, "message" => "Missing Permissions"}
      capture(403, JSON.encode!(error))

      assert {:error, {403, ^error}} =
               apply(Lingo, unquote(function), unquote(Macro.escape(args)))

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

    assert {:error, {400, ^error}} = Lingo.add_invite_target_users("test-invite", user_ids)
    assert_received {:request, :post, _, _, {"application/json", body}}
    assert JSON.decode!(IO.iodata_to_binary(body)) == %{"user_ids" => user_ids}
    refute_received {:request, _, _, _, _}
  end
end
