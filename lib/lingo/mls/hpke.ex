defmodule Lingo.MLS.HPKE do
  @moduledoc false

  # HPKE (RFC 9180) in base mode with DHKEM(P-256, HKDF-SHA256), HKDF-SHA256
  # and AES-128-GCM, the single configuration MLS ciphersuite 2 needs.
  #
  # Public keys are uncompressed SEC1 points (65 bytes), private keys are
  # 32 byte big-endian scalars.

  alias Lingo.MLS.Crypto

  @kem_suite "KEM" <> <<0x0010::16>>
  @hpke_suite "HPKE" <> <<0x0010::16, 0x0001::16, 0x0001::16>>

  # order of the P-256 group, private keys must lie in [1, n)
  @order 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551

  @spec generate_key_pair() :: {public :: binary(), private :: binary()}
  def generate_key_pair do
    {public_key, private_key} = :crypto.generate_key(:ecdh, :prime256v1)
    {public_key, pad_scalar(private_key)}
  end

  @spec public_key(binary()) :: binary()
  def public_key(private_key) do
    {public_key, _private_key} = :crypto.generate_key(:ecdh, :prime256v1, private_key)
    public_key
  end

  @doc "Deterministically derives a key pair from `ikm` (RFC 9180, section 7.1.3)."
  @spec derive_key_pair(binary()) :: {public :: binary(), private :: binary()}
  def derive_key_pair(ikm) do
    prk = labeled_extract(@kem_suite, "", "dkp_prk", ikm)

    private_key =
      Enum.find_value(0..255, fn counter ->
        candidate = labeled_expand(@kem_suite, prk, "candidate", <<counter>>, 32)
        scalar = :binary.decode_unsigned(candidate)
        if scalar != 0 and scalar < @order, do: candidate
      end) || raise "DeriveKeyPair failed"

    {public_key(private_key), private_key}
  end

  @spec seal(binary(), iodata(), iodata(), iodata()) :: {binary(), binary()}
  def seal(recipient_public_key, info, aad, plaintext) do
    {shared_secret, enc} = encap(recipient_public_key)
    {key, nonce} = key_schedule(shared_secret, info)
    {enc, Crypto.seal(key, nonce, aad, plaintext)}
  end

  @spec open(binary(), binary(), iodata(), iodata(), binary()) :: {:ok, binary()} | :error
  def open(recipient_private_key, enc, info, aad, ciphertext) do
    with {:ok, shared_secret} <- decap(enc, recipient_private_key) do
      {key, nonce} = key_schedule(shared_secret, info)
      Crypto.open(key, nonce, aad, ciphertext)
    end
  end

  ## DHKEM (RFC 9180, section 4.1)

  defp encap(recipient_public_key) do
    {enc, ephemeral_private_key} = generate_key_pair()
    dh = :crypto.compute_key(:ecdh, recipient_public_key, ephemeral_private_key, :prime256v1)
    {extract_and_expand(dh, enc <> recipient_public_key), enc}
  end

  defp decap(enc, recipient_private_key) do
    dh = :crypto.compute_key(:ecdh, enc, recipient_private_key, :prime256v1)
    {:ok, extract_and_expand(dh, enc <> public_key(recipient_private_key))}
  rescue
    # an invalid point from the peer
    ErlangError -> :error
  end

  defp extract_and_expand(dh, kem_context) do
    prk = labeled_extract(@kem_suite, "", "eae_prk", dh)
    labeled_expand(@kem_suite, prk, "shared_secret", kem_context, 32)
  end

  ## Key schedule for mode_base without a PSK (RFC 9180, section 5.1)

  defp key_schedule(shared_secret, info) do
    psk_id_hash = labeled_extract(@hpke_suite, "", "psk_id_hash", "")
    info_hash = labeled_extract(@hpke_suite, "", "info_hash", info)
    context = [<<0>>, psk_id_hash, info_hash]

    secret = labeled_extract(@hpke_suite, shared_secret, "secret", "")
    key = labeled_expand(@hpke_suite, secret, "key", context, Crypto.key_size())
    nonce = labeled_expand(@hpke_suite, secret, "base_nonce", context, Crypto.nonce_size())
    {key, nonce}
  end

  defp labeled_extract(suite, salt, label, ikm),
    do: Crypto.extract(salt, ["HPKE-v1", suite, label, ikm])

  defp labeled_expand(suite, prk, label, info, length),
    do: Crypto.expand(prk, [<<length::16>>, "HPKE-v1", suite, label, info], length)

  defp pad_scalar(scalar) when byte_size(scalar) < 32,
    do: :binary.copy(<<0>>, 32 - byte_size(scalar)) <> scalar

  defp pad_scalar(scalar), do: scalar
end
