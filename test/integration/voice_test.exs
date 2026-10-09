defmodule Lingo.Integration.VoiceTest do
  @moduledoc false

  # Three real bots join the same voice channel and must hear each other
  # byte for byte, through DAVE end-to-end encryption.
  #
  # Needs TEVY_E2E_TOKEN_1..3 and TEVY_E2E_GUILD, a guild with a voice
  # channel all three bots can join (TEVY_E2E_VOICE_CHANNEL picks one).

  use ExUnit.Case

  alias Lingo.Test.VoiceBot
  alias Lingo.Voice.Connection

  @moduletag :integration
  @moduletag timeout: 180_000

  @packets 100

  setup_all do
    tokens = for n <- 1..3, do: System.get_env("TEVY_E2E_TOKEN_#{n}")
    guild_id = System.get_env("TEVY_E2E_GUILD")

    if Enum.any?([guild_id | tokens], &(&1 in [nil, ""])),
      do: raise("TEVY_E2E_TOKEN_1..3 and TEVY_E2E_GUILD must be set")

    %{tokens: tokens, guild_id: guild_id, channel_id: voice_channel(hd(tokens), guild_id)}
  end

  defp voice_channel(token, guild_id) do
    System.get_env("TEVY_E2E_VOICE_CHANNEL") || first_voice_channel(token, guild_id)
  end

  defp first_voice_channel(token, guild_id) do
    headers = [{"authorization", "Bot #{token}"}, {"user-agent", "DiscordBot (lingo tests, 1)"}]

    {:ok, %{status: 200, body: body}} =
      Lingo.Api.HTTP.request(
        :get,
        "https://discord.com/api/v10/guilds/#{guild_id}/channels",
        headers
      )

    body |> JSON.decode!() |> Enum.find(&(&1["type"] == 2)) |> Map.fetch!("id")
  end

  # forwards one connection's events to the test, tagged with the bot
  defp listener(test, name) do
    spawn_link(fn -> forward(test, name) end)
  end

  defp forward(test, name) do
    receive do
      {:lingo_voice, _guild_id, event} -> send(test, {name, event})
    end

    forward(test, name)
  end

  defp packets(name),
    do:
      for(
        n <- 1..@packets,
        do: <<0xFC, "#{name}:", n::16, :crypto.strong_rand_bytes(40)::binary>>
      )

  test "three bots hear each other through DAVE", %{
    tokens: tokens,
    guild_id: guild_id,
    channel_id: channel_id
  } do
    names = [:one, :two, :three]

    bots =
      for {name, token} <- Enum.zip(names, tokens), into: %{} do
        {:ok, bot} = VoiceBot.start(token)
        {name, bot}
      end

    user_ids =
      Map.new(bots, fn {name, bot} -> {name, String.to_integer(VoiceBot.user_id(bot))} end)

    on_exit(fn -> for {_name, bot} <- bots, do: VoiceBot.stop(bot, guild_id) end)

    # join one after another, as people do; the group grows a member at a time
    connections =
      for name <- names, into: %{} do
        {:ok, opts} = VoiceBot.join_voice(bots[name], guild_id, channel_id)
        {:ok, connection} = Connection.start_link([subscriber: listener(self(), name)] ++ opts)
        assert_receive {^name, :ready}, 30_000
        {name, connection}
      end

    # wait for the MLS group to settle with all three members
    wait_until(fn ->
      infos = Enum.map(connections, fn {_name, connection} -> Connection.info(connection) end)

      Enum.all?(infos, & &1.dave_active?) and
        length(Enum.uniq_by(infos, & &1.epoch_authenticator)) == 1
    end)

    for {_name, connection} <- connections do
      assert %{dave_protocol_version: 1, dave_active?: true} = Connection.info(connection)
    end

    sent = Map.new(names, &{&1, packets(&1)})
    for name <- names, do: Connection.play(connections[name], sent[name])

    received = collect(names, %{}, System.monotonic_time(:millisecond) + 15_000)

    for listener <- names, speaker <- names, listener != speaker do
      # the silence frames that end playback travel unencrypted, by design
      heard =
        received
        |> Map.get({listener, user_ids[speaker]}, [])
        |> Enum.reject(&(&1 == <<0xF8, 0xFF, 0xFE>>))

      expected = MapSet.new(sent[speaker])

      # every packet heard is exactly one that was sent; UDP may drop a few
      unexpected = Enum.reject(heard, &MapSet.member?(expected, &1))

      assert unexpected == [],
             "#{listener} heard from #{speaker}: #{inspect(Enum.take(unexpected, 3), limit: 12)}"

      assert length(Enum.uniq(heard)) >= @packets * 0.8,
             "#{listener} heard only #{length(Enum.uniq(heard))} of #{@packets} packets from #{speaker}"
    end

    for {_name, connection} <- connections, do: Connection.disconnect(connection)
  end

  defp collect(names, received, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    receive do
      {name, {:audio, user_id, %{opus: opus}}} ->
        received = Map.update(received, {name, user_id}, [opus], &[opus | &1])
        collect(names, received, deadline)

      {_name, _event} ->
        collect(names, received, deadline)
    after
      max(remaining, 0) -> received
    end
  end

  defp wait_until(fun, attempts \\ 60) do
    cond do
      fun.() -> :ok
      attempts == 0 -> flunk("the voice group never settled")
      true -> Process.sleep(500) && wait_until(fun, attempts - 1)
    end
  end
end
