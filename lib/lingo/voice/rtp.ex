defmodule Lingo.Voice.RTP do
  @moduledoc false

  # RTP packets with Discord's transport encryption: the "rtpsize" AEAD modes.
  #
  #   header | ciphertext + tag | 4 byte nonce counter
  #
  # The unencrypted header (fixed part, CSRCs and the extension preamble) is
  # the AAD; the header extension body is encrypted along with the payload.
  # The counter goes at the start of the nonce, zero padded to 12 bytes for
  # AES-256-GCM and to 24 bytes for XChaCha20-Poly1305.

  import Bitwise

  @payload_type 0x78
  @modes ["aead_aes256_gcm_rtpsize", "aead_xchacha20_poly1305_rtpsize"]

  @type header :: %{
          sequence: non_neg_integer(),
          timestamp: non_neg_integer(),
          ssrc: non_neg_integer()
        }

  @doc "Picks the preferred mode the server offers."
  @spec choose_mode([String.t()]) :: String.t() | nil
  def choose_mode(available), do: Enum.find(@modes, &(&1 in available))

  @spec encrypt(String.t(), binary(), header(), non_neg_integer(), binary()) :: binary()
  def encrypt(mode, key, header, nonce, payload) do
    header = <<0x80, @payload_type, header.sequence::16, header.timestamp::32, header.ssrc::32>>

    [header, seal(mode, key, <<nonce::32>>, header, payload), <<nonce::32>>]
    |> IO.iodata_to_binary()
  end

  @doc "Decrypts an RTP packet; returns its header fields and the Opus payload."
  @spec decrypt(String.t(), binary(), binary()) :: {:ok, header(), binary()} | :error
  def decrypt(mode, key, packet) do
    with <<2::2, padding::1, extension::1, csrc_count::4, _marker::1, @payload_type::7,
           sequence::16, timestamp::32, ssrc::32, _rest::binary>> <- packet,
         header_size = 12 + 4 * csrc_count + 4 * extension,
         true <- byte_size(packet) >= header_size + 4 + 16,
         <<header::binary-size(^header_size), sealed::binary>> = packet,
         sealed_size = byte_size(sealed) - 4,
         <<sealed::binary-size(^sealed_size), nonce::binary-4>> = sealed,
         {:ok, plaintext} <- open(mode, key, nonce, header, sealed),
         skip = extension_size(header, extension),
         <<_extension::binary-size(^skip), payload::binary>> <- plaintext,
         {:ok, payload} <- unpad(payload, padding) do
      {:ok, %{sequence: sequence, timestamp: timestamp, ssrc: ssrc}, payload}
    else
      _invalid -> :error
    end
  end

  # the extension preamble ends the header and counts the encrypted body in words
  defp extension_size(_header, 0), do: 0

  defp extension_size(header, 1),
    do: 4 * :binary.decode_unsigned(binary_part(header, byte_size(header), -2))

  defp unpad(payload, 0), do: {:ok, payload}
  defp unpad(<<>>, 1), do: :error

  defp unpad(payload, 1) do
    padding = :binary.last(payload)

    if padding <= byte_size(payload),
      do: {:ok, binary_part(payload, 0, byte_size(payload) - padding)},
      else: :error
  end

  @doc "Whether a datagram is an RTP voice packet (rather than RTCP or IP discovery)."
  @spec voice_packet?(binary()) :: boolean()
  def voice_packet?(<<2::2, _::6, _marker::1, @payload_type::7, _::binary>>), do: true
  def voice_packet?(_packet), do: false

  ## AEAD

  defp seal("aead_aes256_gcm_rtpsize", key, counter, aad, plaintext) do
    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, counter <> <<0::64>>, plaintext, aad, true)

    ciphertext <> tag
  end

  defp seal("aead_xchacha20_poly1305_rtpsize", key, counter, aad, plaintext) do
    {subkey, nonce} = xchacha_key(key, counter <> <<0::160>>)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:chacha20_poly1305, subkey, nonce, plaintext, aad, true)

    ciphertext <> tag
  end

  defp open(_mode, _key, _counter, _aad, sealed) when byte_size(sealed) < 16, do: :error

  defp open(mode, key, counter, aad, sealed) do
    size = byte_size(sealed) - 16
    <<ciphertext::binary-size(^size), tag::binary-16>> = sealed

    result =
      case mode do
        "aead_aes256_gcm_rtpsize" ->
          :crypto.crypto_one_time_aead(
            :aes_256_gcm,
            key,
            counter <> <<0::64>>,
            ciphertext,
            aad,
            tag,
            false
          )

        "aead_xchacha20_poly1305_rtpsize" ->
          {subkey, nonce} = xchacha_key(key, counter <> <<0::160>>)

          :crypto.crypto_one_time_aead(
            :chacha20_poly1305,
            subkey,
            nonce,
            ciphertext,
            aad,
            tag,
            false
          )
      end

    if result == :error, do: :error, else: {:ok, result}
  end

  # XChaCha20-Poly1305 is ChaCha20-Poly1305 under a subkey derived with HChaCha20
  # from the first 16 nonce bytes, using the last 8 as the nonce
  defp xchacha_key(key, <<prefix::binary-16, suffix::binary-8>>),
    do: {hchacha20(key, prefix), <<0::32, suffix::binary>>}

  @doc """
  HChaCha20 (draft-irtf-cfrg-xchacha, section 2.2). :crypto has no direct
  call for it, but a ChaCha20 keystream block is the round output plus the
  input state, so subtracting the input recovers the words HChaCha20 needs.
  """
  @spec hchacha20(binary(), binary()) :: binary()
  def hchacha20(key, <<_::binary-16>> = nonce) do
    keystream = :crypto.crypto_one_time(:chacha20, key, nonce, <<0::512>>, true)
    input = words("expand 32-byte k" <> key <> nonce)
    rounds = Enum.zip_with(words(keystream), input, fn k, s -> k - s &&& 0xFFFFFFFF end)

    (Enum.slice(rounds, 0..3) ++ Enum.slice(rounds, 12..15))
    |> Enum.map(&<<&1::32-little>>)
    |> IO.iodata_to_binary()
  end

  defp words(binary), do: for(<<word::32-little <- binary>>, do: word)

  ## IP discovery

  @spec discovery_request(non_neg_integer()) :: binary()
  def discovery_request(ssrc), do: <<1::16, 70::16, ssrc::32, 0::512, 0::16>>

  @spec parse_discovery(binary()) :: {:ok, String.t(), non_neg_integer()} | :error
  def parse_discovery(<<2::16, 70::16, _ssrc::32, address::binary-64, port::16>>) do
    [ip | _] = :binary.split(address, <<0>>)
    {:ok, ip, port}
  end

  def parse_discovery(_packet), do: :error
end
