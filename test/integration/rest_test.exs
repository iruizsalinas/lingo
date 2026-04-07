defmodule Lingo.Integration.RestTest do
  @moduledoc false
  use Lingo.IntegrationCase

  describe "GET /users/@me" do
    test "returns the bot's own user" do
      assert {:ok, user} = Lingo.Api.User.get_current()
      assert is_binary(user.id)
      assert is_binary(user.username)
      assert user.bot == true
    end
  end

  describe "GET /users/{user.id}" do
    test "fetches the bot's own user by ID", _ctx do
      {:ok, me} = Lingo.Api.User.get_current()

      assert {:ok, user} = Lingo.Api.User.get(me.id)
      assert user.id == me.id
      assert user.username == me.username
    end

    test "returns error for nonexistent user" do
      assert {:error, {404, _body}} = Lingo.Api.User.get("1")
    end
  end

  describe "GET /gateway/bot" do
    test "returns gateway URL and shard info" do
      token = Lingo.Config.token()

      headers = [
        {"authorization", "Bot #{token}"},
        {"user-agent", "DiscordBot (https://github.com/iruizsalinas/lingo, 0.2.1)"}
      ]

      assert {:ok, %{status: 200, body: body}} =
               Req.get("https://discord.com/api/v10/gateway/bot", headers: headers)

      assert is_binary(body["url"])
      assert body["url"] =~ "wss://"
      assert is_integer(body["shards"])
      assert body["shards"] >= 1
      assert is_map(body["session_start_limit"])
      assert is_integer(body["session_start_limit"]["total"])
      assert is_integer(body["session_start_limit"]["remaining"])
      assert is_integer(body["session_start_limit"]["max_concurrency"])
    end
  end

  describe "GET /applications/@me" do
    test "returns the bot's application info" do
      {:ok, %{status: 200, body: body}} =
        Req.get("https://discord.com/api/v10/applications/@me",
          headers: [
            {"authorization", "Bot #{Lingo.Config.token()}"},
            {"user-agent", "DiscordBot (https://github.com/iruizsalinas/lingo, 0.2.1)"}
          ]
        )

      assert is_binary(body["id"])
      assert is_binary(body["name"])
      assert is_map(body["owner"]) or is_nil(body["owner"])
    end
  end

  describe "GET /voice/regions" do
    test "returns a list of voice regions" do
      {:ok, %{status: 200, body: body}} =
        Req.get("https://discord.com/api/v10/voice/regions",
          headers: [
            {"authorization", "Bot #{Lingo.Config.token()}"},
            {"user-agent", "DiscordBot (https://github.com/iruizsalinas/lingo, 0.2.1)"}
          ]
        )

      assert is_list(body)
      assert length(body) > 0

      region = hd(body)
      assert is_binary(region["id"])
      assert is_binary(region["name"])
      assert is_boolean(region["optimal"])
    end
  end

  describe "invite target users" do
    setup do
      guild_id = System.get_env("GUILD_ID")

      if is_nil(guild_id) or guild_id == "" do
        raise "GUILD_ID not set - add it to .env.local"
      end

      # get the first text channel
      {:ok, channels} = Lingo.Api.Guild.get_channels(guild_id)
      channel = Enum.find(channels, fn c -> c.type == :guild_text end)

      # create a temporary invite
      {:ok, invite} = Lingo.Api.Channel.create_invite(channel.id, %{max_age: 300, unique: true})

      on_exit(fn -> Lingo.Api.Invite.delete(invite.code) end)

      %{invite_code: invite.code}
    end

    test "get_target_users returns 404 on fresh invite", %{invite_code: code} do
      assert {:error, {404, _}} = Lingo.Api.Invite.get_target_users(code)
    end

    test "get_target_users_status returns 404 when no job exists", %{invite_code: code} do
      assert {:error, {404, _}} = Lingo.Api.Invite.get_target_users_status(code)
    end

    test "set, get, and status round-trip", %{invite_code: code} do
      {:ok, me} = Lingo.Api.User.get_current()

      # set target users
      result = Lingo.Api.Invite.set_target_users(code, [me.id])
      assert result == :ok or match?({:ok, _}, result)

      # check job status, should exist now
      assert {:ok, status} = Lingo.Api.Invite.get_target_users_status(code)
      assert is_map(status)
      assert is_integer(status["status"])

      # wait for async processing
      Process.sleep(3_000)

      # get target users
      assert {:ok, ids} = Lingo.Api.Invite.get_target_users(code)
      assert is_list(ids)
      assert me.id in ids
    end

    test "returns error for invalid invite code" do
      assert {:error, {404, _}} = Lingo.Api.Invite.get_target_users("invalid_code_xyz")
      assert {:error, {404, _}} = Lingo.Api.Invite.set_target_users("invalid_code_xyz", ["123"])
      assert {:error, {404, _}} = Lingo.Api.Invite.get_target_users_status("invalid_code_xyz")
    end
  end

  describe "rate limit headers" do
    test "Discord returns rate limit headers on API responses" do
      {:ok, resp} =
        Req.get("https://discord.com/api/v10/users/@me",
          headers: [
            {"authorization", "Bot #{Lingo.Config.token()}"},
            {"user-agent", "DiscordBot (https://github.com/iruizsalinas/lingo, 0.2.1)"}
          ]
        )

      assert resp.status == 200

      headers = resp.headers

      assert Map.has_key?(headers, "x-ratelimit-bucket"),
             "Expected x-ratelimit-bucket header, got: #{inspect(Map.keys(headers))}"

      assert Map.has_key?(headers, "x-ratelimit-remaining")
      assert Map.has_key?(headers, "x-ratelimit-limit")
    end
  end
end
