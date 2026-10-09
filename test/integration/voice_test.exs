defmodule Lingo.Integration.VoiceTest do
  @moduledoc false

  # Three real bots in one voice channel, hearing each other through DAVE
  # end-to-end encryption.
  #
  # Needs TEST_BOT_TOKEN_1..3 and TEST_GUILD_ID, a guild with a voice
  # channel all three bots can join (TEST_VOICE_CHANNEL_ID picks one). The
  # real-audio test also needs ffmpeg, to make the audio and to decode what
  # was heard.

  use ExUnit.Case

  import Bitwise

  alias Lingo.Test.{OggWriter, VoiceBot}
  alias Lingo.Voice.{Connection, FFmpeg, Ogg, Opus, WebM}

  @moduletag :integration
  @moduletag timeout: 300_000

  @names [:one, :two, :three]
  @silence <<0xF8, 0xFF, 0xFE>>

  setup_all do
    tokens = for n <- 1..3, do: System.get_env("TEST_BOT_TOKEN_#{n}")
    guild_id = System.get_env("TEST_GUILD_ID")

    if Enum.any?([guild_id | tokens], &(&1 in [nil, ""])),
      do: raise("TEST_BOT_TOKEN_1..3 and TEST_GUILD_ID must be set")

    bots =
      for {name, token} <- Enum.zip(@names, tokens), into: %{} do
        {:ok, bot} = VoiceBot.start(token)
        {name, bot}
      end

    on_exit(fn -> for {_name, bot} <- bots, do: VoiceBot.stop(bot, guild_id) end)

    user_ids =
      Map.new(bots, fn {name, bot} -> {name, String.to_integer(VoiceBot.user_id(bot))} end)

    %{
      bots: bots,
      user_ids: user_ids,
      guild_id: guild_id,
      channel_id: voice_channel(hd(tokens), guild_id)
    }
  end

  # every test starts with nobody in the channel
  setup %{bots: bots, guild_id: guild_id} do
    on_exit(fn ->
      for {_name, bot} <- bots, do: VoiceBot.leave_voice(bot, guild_id)
      Process.sleep(1_000)
    end)
  end

  test "three bots hear each other through DAVE", context do
    connections = join_all(context)

    # For 10 s after a key change receivers still take unencrypted frames, as
    # libdave does, so clients mid-upgrade aren't cut off. Past that, only
    # frames DAVE-encrypted with the group's keys can be heard at all.
    Process.sleep(10_500)

    # real Opus, so whoever is listening in the channel hears clean tones: a
    # chord in 20 ms frames, a low-bitrate mono take in 60 ms frames, and the
    # chord again in 2.5 ms frames, 800 tiny packets
    sent = %{
      one: fixture("stereo_20ms.opus", 100),
      two: fixture("mono_60ms.opus", 34),
      three: fixture("stereo_2_5ms.opus", 800)
    }

    for name <- @names, do: Connection.play(connections[name], sent[name])
    received = collect(15_000)

    for {listener, speaker} <- pairs() do
      events = audio(received, listener, context.user_ids[speaker])
      assert_exact(events, sent[speaker], listener, speaker)
    end
  end

  @tag :ffmpeg
  @tag :tmp_dir
  test "real audio, three ways: WebM as is, mp3 through ffmpeg, Ogg at 60 ms frames", context do
    dir = context.tmp_dir
    tones = %{one: 440, two: 660, three: 880}

    webm = encode(dir, "one.webm", 440, ~w(-c:a libopus -b:a 96k))
    mp3 = encode(dir, "two.mp3", 660, ~w(-c:a libmp3lame -b:a 128k))
    ogg = encode(dir, "three.opus", 880, ~w(-ac 1 -c:a libopus -b:a 32k -frame_duration 60))

    expected = %{
      one: WebM.stream!(webm) |> Enum.to_list(),
      # ffmpeg is deterministic: a second run gives the packets playback will send
      two: FFmpeg.stream(mp3) |> Enum.to_list(),
      three: Ogg.stream!(ogg) |> Enum.to_list()
    }

    connections = join_all(context)

    Connection.play(connections.one, WebM.stream!(webm))
    Connection.play(connections.two, FFmpeg.stream(mp3))
    Connection.play(connections.three, Ogg.stream!(ogg))

    received = collect(12_000)

    for name <- @names do
      assert Enum.any?(received, &match?({^name, :playback_finished, _at}, &1)),
             "#{name} never finished playing"
    end

    for {listener, speaker} <- pairs() do
      events = audio(received, listener, context.user_ids[speaker])
      heard = Enum.map(events, & &1.opus)

      # exact bytes at exact positions, and timestamps that add up
      assert_exact(events, expected[speaker], listener, speaker)

      # paced in real time: three seconds of audio take about three seconds
      span = List.last(events).at - hd(events).at
      assert span in 2_500..3_600, "#{listener} heard #{speaker}'s 3 s over #{span} ms"

      # and it decodes to the speaker's own tone, which drowns out the others
      # thousands of times over, even with a tenth of the packets lost
      powers = tone_powers(dir, heard, Map.values(tones))
      {own, others} = Map.pop(powers, tones[speaker])

      assert own > 1_000 * Enum.max(Map.values(others)),
             "#{listener} didn't hear #{speaker}'s #{tones[speaker]} Hz tone: #{inspect(powers)}"
    end
  end

  test "audio keeps flowing while people join, leave and come back", context do
    one = join(context, :one)
    two = join(context, :two)
    wait_for_group([one, two])

    # 45 s of audio from :one while the group changes around it; the last
    # 15 s or so are past every key change's 10 s plaintext grace
    packets = fixture("stereo_20ms.opus", 2_250)
    Connection.play(one, packets)

    Process.sleep(3_000)
    three = join(context, :three)
    wait_for_group([one, two, three])

    Process.sleep(2_000)
    Connection.disconnect(two)
    VoiceBot.leave_voice(context.bots.two, context.guild_id)
    wait_for_group([one, three])

    Process.sleep(2_000)
    two = join(context, :two)
    wait_for_group([one, two, three])

    received = collect_until(&match?({:one, :playback_finished, _}, &1), 60_000)
    speaker = context.user_ids.one

    # where each heard packet sits among those sent; the audio loops every
    # second, so only the distances between them are meaningful
    numbers = fn listener ->
      events = audio(received, listener, speaker)
      positions = positions(events, packets)
      assert positions, "#{listener} heard packets that don't match what was sent"
      positions
    end

    # :two hears its first session, a gap while it is away, then its second
    {first, second} = split_at_largest_gap(numbers.(:two))
    assert_continuous(first, "two, first session")
    assert_continuous(second, "two, after rejoining")

    # :three joins mid-stream and hears everything from then on, through
    # :two leaving and coming back
    assert_continuous(numbers.(:three), "three")

    # and both hear it to the very end
    [finished] = for {:one, :playback_finished, at} <- received, do: at

    for listener <- [:two, :three] do
      last = received |> audio(listener, speaker) |> List.last()

      assert finished - last.at < 500,
             "#{listener} stopped hearing #{finished - last.at} ms early"
    end

    assert Connection.info(three).dave_active?
    assert Connection.info(two).epoch_authenticator == Connection.info(one).epoch_authenticator
  end

  test "replacing and stopping playback, and a source that fails", context do
    connections = join_all(context)
    one = connections.one

    # two different recordings, so every packet heard tells which one it came from
    a = fixture("stereo_20ms.opus", 500)
    b = fixture("mono_60ms.opus", 170)
    assert MapSet.disjoint?(MapSet.new(a), MapSet.new(b))

    Connection.play(one, a)
    Process.sleep(1_000)
    Connection.play(one, b)
    Process.sleep(1_000)
    Connection.stop_playback(one)
    Process.sleep(500)

    # the replaced source never finishes, the stopped one is just stopped
    Connection.play(one, Stream.map([:boom], fn _ -> raise ArgumentError, "bad source" end))

    received = collect(3_000)
    heard = heard(received, :two, context.user_ids.one)
    a = MapSet.new(a)
    b = MapSet.new(b)

    # a second of each: 50 packets of 20 ms, then about 16 of 60 ms
    {as, bs} = Enum.split_while(heard, &MapSet.member?(a, &1))
    assert length(as) in 30..55 and length(bs) in 10..19, "#{length(as)} then #{length(bs)}"
    assert Enum.all?(bs, &MapSet.member?(b, &1)), "audio from the replaced source leaked through"

    refute Enum.any?(received, &match?({:one, :playback_finished, _}, &1))

    assert Enum.any?(
             received,
             &match?({:one, {:playback_failed, %ArgumentError{message: "bad source"}}, _}, &1)
           )

    assert Enum.any?(received, fn
             {:two, {:speaking, user_id, flags}, _} ->
               user_id == context.user_ids.one and flags > 0

             _other ->
               false
           end)
  end

  ## Joining

  defp join_all(context) do
    # one after another, as people do; the group grows a member at a time
    connections = Map.new(@names, &{&1, join(context, &1)})
    wait_for_group(Map.values(connections))
    connections
  end

  defp join(context, name) do
    {:ok, opts} = VoiceBot.join_voice(context.bots[name], context.guild_id, context.channel_id)
    {:ok, connection} = Connection.start_link([subscriber: listener(self(), name)] ++ opts)
    assert_receive {^name, :ready, _at}, 30_000
    connection
  end

  # DAVE is on everywhere and everyone holds the same group keys
  defp wait_for_group(connections, attempts \\ 60) do
    infos = Enum.map(connections, &Connection.info/1)

    settled? =
      Enum.all?(infos, & &1.dave_active?) and
        length(Enum.uniq_by(infos, & &1.epoch_authenticator)) == 1

    cond do
      settled? -> :ok
      attempts == 0 -> flunk("the voice group never settled: #{inspect(infos, limit: 3)}")
      true -> Process.sleep(250) && wait_for_group(connections, attempts - 1)
    end
  end

  # forwards one connection's events to the test, tagged with the bot and the time
  defp listener(test, name), do: spawn_link(fn -> forward(test, name) end)

  defp forward(test, name) do
    receive do
      {:lingo_voice, _guild_id, event} ->
        send(test, {name, event, System.monotonic_time(:millisecond)})
    end

    forward(test, name)
  end

  ## Hearing

  defp collect(timeout), do: collect_until(fn _event -> false end, timeout)

  # events until `done?` matches one, then two more seconds for stragglers
  defp collect_until(done?, timeout),
    do: collect_until([], done?, System.monotonic_time(:millisecond) + timeout)

  defp collect_until(received, done?, deadline) do
    receive do
      {_name, _event, _at} = event ->
        deadline =
          if done?.(event), do: System.monotonic_time(:millisecond) + 2_000, else: deadline

        collect_until([event | received], done?, deadline)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> Enum.reverse(received)
    end
  end

  defp audio(received, listener, user_id) do
    for {^listener, {:audio, ^user_id, packet}, at} <- received,
        # the silence frames that end playback travel unencrypted, by design
        packet.opus != @silence,
        do: Map.put(packet, :at, at)
  end

  defp heard(received, listener, user_id),
    do: received |> audio(listener, user_id) |> Enum.map(& &1.opus)

  defp pairs, do: for(a <- @names, b <- @names, a != b, do: {a, b})

  # Each heard packet is exactly the one sent at its place, which its RTP
  # sequence number gives (a tone repeats packets, so bytes alone can't), and
  # its timestamp is the duration of everything sent before it. UDP may drop
  # a few.
  defp assert_exact(events, sent, listener, speaker) do
    label = "#{listener} hearing #{speaker}"
    assert events != [], "#{label}: nothing"

    positions = positions(events, sent)
    assert positions, "#{label}: packets that don't match what was sent where they were sent"

    elapsed = sent |> Enum.scan(0, &(Opus.samples(&1) + &2)) |> List.to_tuple()
    before = fn position -> if position == 0, do: 0, else: elem(elapsed, position - 1) end
    [start | _] = positions
    first = hd(events)

    for {event, position} <- Enum.zip(events, positions) do
      assert (event.timestamp - first.timestamp &&& 0xFFFFFFFF) ==
               before.(position) - before.(start),
             "#{label}: wrong timestamp at packet #{position}"
    end

    assert length(Enum.uniq(positions)) == length(positions), "#{label}: duplicates"

    assert length(positions) >= length(sent) * 0.9,
           "#{label}: #{length(positions)} of #{length(sent)}"
  end

  # The place in `sent` of each heard packet, from its RTP sequence number
  # (sent audio repeats packets, so bytes alone can't tell), or nil when any
  # packet isn't exactly the one sent at its place.
  defp positions(events, sent) do
    sent = List.to_tuple(sent)
    first = hd(events)
    offsets = Enum.map(events, &(&1.sequence - first.sequence &&& 0xFFFF))

    Enum.find_value(0..(tuple_size(sent) - 1), fn start ->
      positions = Enum.map(offsets, &(start + &1))

      if Enum.all?(Enum.zip(events, positions), fn {event, position} ->
           position < tuple_size(sent) and elem(sent, position) == event.opus
         end),
         do: positions
    end)
  end

  defp split_at_largest_gap(numbers) do
    {_gap, index} =
      numbers
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.with_index()
      |> Enum.map(fn {[a, b], index} -> {b - a, index} end)
      |> Enum.max()

    Enum.split(numbers, index + 1)
  end

  # a few lost packets are UDP; a hole of more than 300 ms is a broken transition
  defp assert_continuous(numbers, label) do
    gaps = numbers |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> b - a end)

    assert Enum.max(gaps, fn -> 1 end) <= 15,
           "#{label}: gaps #{inspect(Enum.filter(gaps, &(&1 > 1)))}"
  end

  ## Audio

  # `count` packets of a fixture, looped
  defp fixture(name, count) do
    Path.join("test/fixtures/audio", name) |> Ogg.stream!() |> Stream.cycle() |> Enum.take(count)
  end

  defp encode(dir, name, frequency, codec_args) do
    path = Path.join(dir, name)
    source = "sine=frequency=#{frequency}:sample_rate=48000:duration=3"
    ffmpeg!(["-f", "lavfi", "-i", source, "-ac", "2"] ++ codec_args ++ [path])
    path
  end

  # decodes the packets and measures the power at each frequency
  defp tone_powers(dir, packets, frequencies) do
    path = Path.join(dir, "heard-#{System.unique_integer([:positive])}.opus")
    head = <<"OpusHead", 1, 2, 312::16-little, 48_000::32-little, 0::16, 0>>
    File.write!(path, OggWriter.file(head, packets))

    pcm = ffmpeg!(["-i", path, "-f", "s16le", "-ac", "1", "-ar", "48000", "pipe:1"])
    samples = for <<sample::16-signed-little <- pcm>>, do: sample

    Map.new(frequencies, &{&1, goertzel(samples, &1)})
  end

  # the signal's power at one frequency
  defp goertzel(samples, frequency) do
    coefficient = 2 * :math.cos(2 * :math.pi() * frequency / 48_000)

    {s1, s2} =
      Enum.reduce(samples, {0.0, 0.0}, fn sample, {s1, s2} ->
        {sample + coefficient * s1 - s2, s1}
      end)

    s1 * s1 + s2 * s2 - coefficient * s1 * s2
  end

  defp ffmpeg!(args) do
    {output, 0} =
      System.cmd(System.find_executable("ffmpeg"), ~w(-hide_banner -loglevel error -y) ++ args)

    output
  end

  defp voice_channel(token, guild_id) do
    System.get_env("TEST_VOICE_CHANNEL_ID") || first_voice_channel(token, guild_id)
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
end
