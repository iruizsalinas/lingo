defmodule Lingo.MLS.Crypto do
  @moduledoc false

  # Primitives for MLS ciphersuite 2, MLS_128_DHKEMP256_AES128GCM_SHA256_P256
  # (RFC 9420, section 5): SHA-256, HKDF-SHA256, AES-128-GCM, HPKE with
  # DHKEM(P-256) and ECDSA P-256 signatures, all on top of :crypto.

  alias Lingo.MLS.{Codec, HPKE}

  @cipher_suite 2
  @hash_size 32
  @key_size 16
  @nonce_size 12

  def cipher_suite, do: @cipher_suite
  def hash_size, do: @hash_size
  def key_size, do: @key_size
  def nonce_size, do: @nonce_size

  @spec hash(iodata()) :: binary()
  def hash(data), do: :crypto.hash(:sha256, data)

  @spec mac(binary(), iodata()) :: binary()
  def mac(key, data), do: :crypto.mac(:hmac, :sha256, key, data)

  @spec random(pos_integer()) :: binary()
  def random(size \\ @hash_size), do: :crypto.strong_rand_bytes(size)

  ## HKDF (RFC 5869)

  @spec extract(binary(), iodata()) :: binary()
  def extract(salt, ikm), do: mac(salt, ikm)

  @spec expand(binary(), iodata(), pos_integer()) :: binary()
  def expand(prk, info, length), do: expand(prk, info, length, <<>>, 1, <<>>)

  defp expand(_prk, _info, length, _block, _counter, okm) when byte_size(okm) >= length,
    do: binary_part(okm, 0, length)

  defp expand(prk, info, length, block, counter, okm) do
    block = mac(prk, [block, info, counter])
    expand(prk, info, length, block, counter + 1, okm <> block)
  end

  ## Labeled derivations (RFC 9420, sections 5.1 and 8)

  @spec expand_with_label(binary(), String.t(), iodata(), pos_integer()) :: binary()
  def expand_with_label(secret, label, context, length) do
    kdf_label = [<<length::16>>, Codec.vector("MLS 1.0 " <> label), Codec.vector(context)]
    expand(secret, kdf_label, length)
  end

  @spec derive_secret(binary(), String.t()) :: binary()
  def derive_secret(secret, label), do: expand_with_label(secret, label, "", @hash_size)

  @spec derive_tree_secret(binary(), String.t(), non_neg_integer(), pos_integer()) :: binary()
  def derive_tree_secret(secret, label, generation, length),
    do: expand_with_label(secret, label, <<generation::32>>, length)

  @spec ref_hash(String.t(), iodata()) :: binary()
  def ref_hash(label, value), do: hash([Codec.vector(label), Codec.vector(value)])

  ## Signatures

  @spec generate_signature_key() :: {public :: binary(), private :: binary()}
  def generate_signature_key, do: HPKE.generate_key_pair()

  @spec sign_with_label(binary(), String.t(), iodata()) :: binary()
  def sign_with_label(private_key, label, content),
    do: :crypto.sign(:ecdsa, :sha256, sign_content(label, content), [private_key, :prime256v1])

  @spec verify_with_label(binary(), String.t(), iodata(), binary()) :: boolean()
  def verify_with_label(public_key, label, content, signature) do
    :crypto.verify(:ecdsa, :sha256, sign_content(label, content), signature, [
      public_key,
      :prime256v1
    ])
  rescue
    # a malformed public key or signature is simply an invalid signature
    ErlangError -> false
  end

  defp sign_content(label, content),
    do: IO.iodata_to_binary([Codec.vector("MLS 1.0 " <> label), Codec.vector(content)])

  ## Public key encryption

  @spec encrypt_with_label(binary(), String.t(), iodata(), binary()) ::
          {kem_output :: binary(), ciphertext :: binary()}
  def encrypt_with_label(public_key, label, context, plaintext),
    do: HPKE.seal(public_key, encrypt_context(label, context), "", plaintext)

  @spec decrypt_with_label(binary(), String.t(), iodata(), binary(), binary()) ::
          {:ok, binary()} | :error
  def decrypt_with_label(private_key, label, context, kem_output, ciphertext),
    do: HPKE.open(private_key, kem_output, encrypt_context(label, context), "", ciphertext)

  defp encrypt_context(label, context),
    do: IO.iodata_to_binary([Codec.vector("MLS 1.0 " <> label), Codec.vector(context)])

  ## Symmetric encryption

  @spec seal(binary(), binary(), iodata(), iodata()) :: binary()
  def seal(key, nonce, aad, plaintext) do
    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_128_gcm, key, nonce, plaintext, aad, true)

    ciphertext <> tag
  end

  @spec open(binary(), binary(), iodata(), binary()) :: {:ok, binary()} | :error
  def open(key, nonce, aad, sealed) when byte_size(sealed) >= 16 do
    ciphertext_size = byte_size(sealed) - 16
    <<ciphertext::binary-size(^ciphertext_size), tag::binary-16>> = sealed

    case :crypto.crypto_one_time_aead(:aes_128_gcm, key, nonce, ciphertext, aad, tag, false) do
      :error -> :error
      plaintext -> {:ok, plaintext}
    end
  end

  def open(_key, _nonce, _aad, _sealed), do: :error
end
