defmodule Lingo.Voice.RTP.AEAD do
  @moduledoc false

  # The AEAD ciphers of the rtpsize modes, including XChaCha20-Poly1305,
  # which :crypto lacks, built on HChaCha20.

  import Bitwise

  def seal("aead_aes256_gcm_rtpsize", key, counter, aad, plaintext) do
    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, counter <> <<0::64>>, plaintext, aad, true)

    ciphertext <> tag
  end

  def seal("aead_xchacha20_poly1305_rtpsize", key, counter, aad, plaintext) do
    {subkey, nonce} = xchacha_key(key, counter <> <<0::160>>)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:chacha20_poly1305, subkey, nonce, plaintext, aad, true)

    ciphertext <> tag
  end

  def open(_mode, _key, _counter, _aad, sealed) when byte_size(sealed) < 16, do: :error

  def open(mode, key, counter, aad, sealed) do
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
  def xchacha_key(key, <<prefix::binary-16, suffix::binary-8>>),
    do: {hchacha20(key, prefix), <<0::32, suffix::binary>>}

  @spec hchacha20(binary(), binary()) :: binary()
  def hchacha20(key, <<_::binary-16>> = nonce) do
    keystream = :crypto.crypto_one_time(:chacha20, key, nonce, <<0::512>>, true)
    input = words("expand 32-byte k" <> key <> nonce)
    rounds = Enum.zip_with(words(keystream), input, fn k, s -> k - s &&& 0xFFFFFFFF end)

    (Enum.slice(rounds, 0..3) ++ Enum.slice(rounds, 12..15))
    |> Enum.map(&<<&1::32-little>>)
    |> IO.iodata_to_binary()
  end

  def words(binary), do: for(<<word::32-little <- binary>>, do: word)
end
