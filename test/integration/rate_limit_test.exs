defmodule Lingo.Integration.RateLimitTest do
  @moduledoc false
  use Lingo.IntegrationCase

  @moduletag timeout: 180_000

  setup do
    guild_id = System.get_env("GUILD_ID")
    if is_nil(guild_id) or guild_id == "", do: raise("GUILD_ID not set")

    {:ok, channel} =
      Lingo.Api.Guild.create_channel(guild_id, %{
        name: "lingo-rl-test-#{:rand.uniform(99999)}",
        type: 0
      })

    on_exit(fn -> Lingo.Api.Channel.delete(channel.id) end)

    %{guild_id: guild_id, channel_id: channel.id}
  end

  describe "per-route rate limits" do
    test "rapid sequential requests all succeed without error", %{channel_id: channel_id} do
      # Send 5 messages quickly, the rate limiter should
      # pace them automatically, never returning an error to us
      results =
        for i <- 1..5 do
          Lingo.Api.Message.create(channel_id, %{content: "rl test #{i}"})
        end

      assert Enum.all?(results, &match?({:ok, _}, &1))
    end

    test "rapid edits to the same message succeed", %{channel_id: channel_id} do
      {:ok, msg} = Lingo.Api.Message.create(channel_id, %{content: "original"})

      results =
        for i <- 1..5 do
          Lingo.Api.Message.edit(channel_id, msg.id, %{content: "edit #{i}"})
        end

      assert Enum.all?(results, &match?({:ok, _}, &1))

      # verify the last edit stuck
      {:ok, final} = Lingo.Api.Message.get(channel_id, msg.id)
      assert final.content == "edit 5"
    end

    test "rapid reaction add/remove cycles succeed", %{channel_id: channel_id} do
      {:ok, msg} = Lingo.Api.Message.create(channel_id, %{content: "reaction rl test"})

      emojis = ["👍", "❤️", "🔥", "⭐", "🎉"]

      # add all reactions
      add_results = Enum.map(emojis, fn e -> Lingo.Api.Reaction.create(channel_id, msg.id, e) end)
      assert Enum.all?(add_results, &(&1 == :ok))

      # remove all reactions
      remove_results =
        Enum.map(emojis, fn e -> Lingo.Api.Reaction.delete_own(channel_id, msg.id, e) end)

      assert Enum.all?(remove_results, &(&1 == :ok))
    end
  end

  describe "bucket isolation" do
    test "requests to different channels don't block each other", %{
      guild_id: guild_id,
      channel_id: channel_id
    } do
      # create a second channel
      {:ok, channel2} =
        Lingo.Api.Guild.create_channel(guild_id, %{
          name: "lingo-rl-test2-#{:rand.uniform(99999)}",
          type: 0
        })

      on_exit(fn -> Lingo.Api.Channel.delete(channel2.id) end)

      # send messages to both channels concurrently
      task1 =
        Task.async(fn ->
          for i <- 1..3 do
            Lingo.Api.Message.create(channel_id, %{content: "ch1 msg #{i}"})
          end
        end)

      task2 =
        Task.async(fn ->
          for i <- 1..3 do
            Lingo.Api.Message.create(channel2.id, %{content: "ch2 msg #{i}"})
          end
        end)

      results1 = Task.await(task1, 30_000)
      results2 = Task.await(task2, 30_000)

      assert Enum.all?(results1, &match?({:ok, _}, &1))
      assert Enum.all?(results2, &match?({:ok, _}, &1))
    end

    test "different endpoint types don't interfere", %{channel_id: channel_id} do
      # mix message creation with channel reads, different buckets
      results =
        for i <- 1..3 do
          msg_result = Lingo.Api.Message.create(channel_id, %{content: "mix #{i}"})
          ch_result = Lingo.Api.Channel.get(channel_id)
          {msg_result, ch_result}
        end

      assert Enum.all?(results, fn {msg, ch} ->
               match?({:ok, _}, msg) and match?({:ok, _}, ch)
             end)
    end
  end

  describe "concurrent request handling" do
    test "parallel message sends to the same channel all succeed", %{channel_id: channel_id} do
      # fire 8 concurrent sends to the same channel
      tasks =
        for i <- 1..8 do
          Task.async(fn ->
            Lingo.Api.Message.create(channel_id, %{content: "parallel #{i}"})
          end)
        end

      results = Enum.map(tasks, &Task.await(&1, 30_000))
      successes = Enum.count(results, &match?({:ok, _}, &1))

      # all should succeed, the rate limiter handles serialization
      assert successes == 8
    end

    test "parallel channel reads under load", %{guild_id: guild_id} do
      tasks =
        for _ <- 1..10 do
          Task.async(fn -> Lingo.Api.Guild.get_channels(guild_id) end)
        end

      results = Enum.map(tasks, &Task.await(&1, 30_000))
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end

  describe "rate limit header tracking" do
    test "ETS buckets are populated after requests", %{channel_id: channel_id} do
      # make a request to populate the bucket
      {:ok, _} = Lingo.Api.Message.create(channel_id, %{content: "bucket check"})

      # check that the rate limiter stored bucket info
      buckets = :ets.tab2list(:lingo_rate_limits)
      assert length(buckets) > 0

      # each entry should have {key, remaining, reset_at, limit}
      Enum.each(buckets, fn {_key, remaining, reset_at, limit} ->
        assert is_integer(remaining)
        assert is_integer(reset_at)
        assert is_integer(limit)
        assert remaining >= 0
        assert limit > 0
      end)
    end

    test "bucket map links route keys to bucket hashes", %{channel_id: channel_id} do
      {:ok, _} = Lingo.Api.Message.create(channel_id, %{content: "map check"})

      mappings = :ets.tab2list(:lingo_bucket_map)
      assert length(mappings) > 0

      Enum.each(mappings, fn {route_key, bucket_key} ->
        assert is_binary(route_key)
        assert is_binary(bucket_key)
      end)
    end
  end

  describe "sustained load" do
    test "20 sequential messages complete without error", %{channel_id: channel_id} do
      results =
        for i <- 1..20 do
          Lingo.Api.Message.create(channel_id, %{content: "sustained #{i}"})
        end

      successes = Enum.count(results, &match?({:ok, _}, &1))
      assert successes == 20
    end

    test "rapid delete cycle -create and delete 10 messages", %{channel_id: channel_id} do
      # delete has a stricter rate limit for old messages, but fresh ones should be fine
      results =
        for i <- 1..10 do
          {:ok, msg} = Lingo.Api.Message.create(channel_id, %{content: "delete-me #{i}"})
          delete_result = Lingo.Api.Message.delete(channel_id, msg.id)
          delete_result
        end

      assert Enum.all?(results, &(&1 == :ok))
    end

    test "mixed CRUD operations under sustained load", %{channel_id: channel_id} do
      # create, edit, get, delete cycle x5
      for i <- 1..5 do
        {:ok, msg} = Lingo.Api.Message.create(channel_id, %{content: "crud #{i}"})
        {:ok, _} = Lingo.Api.Message.edit(channel_id, msg.id, %{content: "edited #{i}"})
        {:ok, fetched} = Lingo.Api.Message.get(channel_id, msg.id)
        assert fetched.content == "edited #{i}"
        :ok = Lingo.Api.Message.delete(channel_id, msg.id)
      end
    end
  end

  describe "global rate limit recovery" do
    test "pause_global and wait_global work correctly" do
      # simulate a 500ms global pause
      Lingo.Api.RateLimiter.pause_global(500)

      start = System.monotonic_time(:millisecond)
      Lingo.Api.RateLimiter.wait_global()
      elapsed = System.monotonic_time(:millisecond) - start

      # should have waited roughly 500ms (+ some buffer)
      assert elapsed >= 400
      assert elapsed < 2000

      # second wait should be instant (pause cleared)
      start2 = System.monotonic_time(:millisecond)
      Lingo.Api.RateLimiter.wait_global()
      elapsed2 = System.monotonic_time(:millisecond) - start2
      assert elapsed2 < 100
    end

    test "requests succeed after global pause expires", %{channel_id: channel_id} do
      # simulate a brief global pause
      Lingo.Api.RateLimiter.pause_global(200)

      # this request should wait for the pause then succeed
      assert {:ok, _} = Lingo.Api.Message.create(channel_id, %{content: "post-pause"})
    end
  end

  describe "cross-resource concurrent load" do
    test "many different resource types in parallel all succeed", %{
      guild_id: guild_id,
      channel_id: channel_id
    } do
      {:ok, me} = Lingo.Api.User.get_current()

      tasks = [
        # messages
        Task.async(fn ->
          {:ok, msg} = Lingo.Api.Message.create(channel_id, %{content: "concurrent 1"})
          {:ok, _} = Lingo.Api.Message.edit(channel_id, msg.id, %{content: "edited"})
          :ok = Lingo.Api.Message.delete(channel_id, msg.id)
          :messages_ok
        end),

        # more messages on the same channel
        Task.async(fn ->
          {:ok, _} = Lingo.Api.Message.create(channel_id, %{content: "concurrent 2"})
          {:ok, _} = Lingo.Api.Message.create(channel_id, %{content: "concurrent 3"})
          :messages2_ok
        end),

        # roles
        Task.async(fn ->
          {:ok, role} =
            Lingo.Api.Role.create(guild_id, %{name: "rl-cross-#{:rand.uniform(99999)}"})

          {:ok, _} = Lingo.Api.Role.modify(guild_id, role.id, %{name: "renamed"})
          Lingo.Api.Role.delete(guild_id, role.id)
          :roles_ok
        end),

        # members
        Task.async(fn ->
          {:ok, _} = Lingo.Api.Member.get(guild_id, me.id)
          {:ok, _} = Lingo.Api.Member.list(guild_id, limit: 2)
          :members_ok
        end),

        # channels
        Task.async(fn ->
          {:ok, _} = Lingo.Api.Channel.get(channel_id)
          {:ok, _} = Lingo.Api.Guild.get_channels(guild_id)
          :channels_ok
        end),

        # guild reads
        Task.async(fn ->
          {:ok, _} = Lingo.Api.Guild.get(guild_id)
          {:ok, _} = Lingo.Api.Role.list(guild_id)
          :guild_ok
        end),

        # reactions
        Task.async(fn ->
          {:ok, msg} = Lingo.Api.Message.create(channel_id, %{content: "react target"})
          :ok = Lingo.Api.Reaction.create(channel_id, msg.id, "🔥")
          :ok = Lingo.Api.Reaction.delete_own(channel_id, msg.id, "🔥")
          :reactions_ok
        end),

        # user endpoints
        Task.async(fn ->
          {:ok, _} = Lingo.Api.User.get_current()
          {:ok, _} = Lingo.Api.User.get(me.id)
          :users_ok
        end)
      ]

      results = Enum.map(tasks, &Task.await(&1, 60_000))

      assert :messages_ok in results
      assert :messages2_ok in results
      assert :roles_ok in results
      assert :members_ok in results
      assert :channels_ok in results
      assert :guild_ok in results
      assert :reactions_ok in results
      assert :users_ok in results
    end

    test "sustained mixed operations in waves", %{guild_id: guild_id, channel_id: channel_id} do
      # 3 waves of mixed operations
      for wave <- 1..3 do
        tasks = [
          Task.async(fn ->
            {:ok, _} = Lingo.Api.Message.create(channel_id, %{content: "wave #{wave} msg"})
          end),
          Task.async(fn ->
            {:ok, _} = Lingo.Api.Guild.get(guild_id)
          end),
          Task.async(fn ->
            {:ok, _} = Lingo.Api.Role.list(guild_id)
          end),
          Task.async(fn ->
            {:ok, _} = Lingo.Api.Member.list(guild_id, limit: 1)
          end)
        ]

        results = Enum.map(tasks, &Task.await(&1, 30_000))
        assert Enum.all?(results, &match?({:ok, _}, &1))
      end
    end
  end
end
