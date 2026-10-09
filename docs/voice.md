# Voice

Lingo can join voice channels, play audio and receive what others say. Discord's end-to-end encryption for voice (DAVE) is built in and always on when the call uses it, so there is nothing to configure.

Voice needs the `:guild_voice_states` intent:

```elixir
{Lingo, bot: MyBot, token: token, intents: [:guilds, :guild_voice_states]}
```

## Joining and Leaving

```elixir
{:ok, _connection} = Lingo.Voice.join(guild_id, channel_id)
Lingo.Voice.leave(guild_id)
```

`join/3` returns once the voice connection is up. Options: `self_mute:`, `self_deaf:` and `timeout:` (milliseconds, default 20000). `Lingo.join_voice/3` and `Lingo.leave_voice/1` do the same.

Moving the bot to another channel is another `join/3`. If Discord moves the bot to a new voice server, Lingo reconnects on its own.

## Playing Audio

Audio is Opus. Lingo has no native dependencies, so it doesn't encode raw PCM itself. There are three ways to play something:

```elixir
# an Ogg Opus file (.opus / .ogg)
Lingo.Voice.play_file(guild_id, "priv/hello.opus")

# anything ffmpeg can read: mp3, wav, a URL... (needs ffmpeg installed)
Lingo.Voice.play_url(guild_id, "https://example.com/song.mp3", bitrate: 96_000)

# any enumerable of Opus packets
Lingo.Voice.play(guild_id, packets)
```

Playing replaces whatever is already playing. `Lingo.Voice.stop(guild_id)` stops it. Packets are paced in real time from their own durations, and playback ends with a few frames of silence, as Discord recommends.

To convert audio ahead of time:

```bash
ffmpeg -i input.mp3 -c:a libopus -ar 48000 -ac 2 -b:a 64k output.opus
```

## Receiving Audio

```elixir
Lingo.Voice.listen(guild_id)

receive do
  {:lingo_voice, ^guild_id, {:audio, user_id, %{opus: opus, sequence: seq, timestamp: ts}}} ->
    # one decrypted Opus packet from user_id
end
```

`listen/1` subscribes the calling process to every event of the guild's voice connection:

| Message | When |
|---------|------|
| `{:lingo_voice, guild_id, :ready}` | The connection is up |
| `{:lingo_voice, guild_id, {:audio, user_id, packet}}` | An Opus packet arrived |
| `{:lingo_voice, guild_id, {:speaking, user_id, flags}}` | Someone started or stopped speaking |
| `{:lingo_voice, guild_id, :playback_finished}` | Our playback ended |
| `{:lingo_voice, guild_id, {:disconnected, reason}}` | The connection closed for good |

Packets come in network order. Some may be missing, which is normal for real-time audio. Decoding Opus to PCM needs an external decoder such as ffmpeg.

## Encryption

Every voice packet is encrypted between the bot and Discord with AES-256-GCM, or XChaCha20-Poly1305 when the server prefers it.

On top of that, DAVE encrypts audio end to end between everyone in the call, using an MLS group (RFC 9420) that Discord's voice server coordinates. Lingo joins the group, follows membership changes, and switches keys exactly when Discord says to.

While end-to-end encryption is on, audio is never sent unencrypted. In particular, a bot alone in a channel holds its audio until someone else joins and the group's keys exist.

`Lingo.Voice.Connection.info/1` reports the current state:

```elixir
Lingo.Voice.connection(guild_id) |> Lingo.Voice.Connection.info()
#=> %{status: :connected, dave_active?: true, dave_protocol_version: 1, epoch_authenticator: <<...>>, ...}
```

Two clients that show the same `epoch_authenticator` share the same keys.
