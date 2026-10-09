defmodule Lingo.MLS.LeafNode do
  @moduledoc false

  # A member's leaf in the ratchet tree (RFC 9420, section 7.2).

  alias Lingo.MLS.{Codec, Crypto}

  @enforce_keys [:encryption_key, :signature_key, :credential, :capabilities, :source]
  defstruct [
    :encryption_key,
    :signature_key,
    :credential,
    :capabilities,
    :source,
    extensions: [],
    signature: <<>>
  ]

  @type credential :: {:basic, binary()} | {:x509, [binary()]}
  @type source ::
          {:key_package, not_before :: non_neg_integer(), not_after :: non_neg_integer()}
          | :update
          | {:commit, parent_hash :: binary()}

  @type t :: %__MODULE__{
          encryption_key: binary(),
          signature_key: binary(),
          credential: credential(),
          capabilities: map(),
          source: source(),
          extensions: [{non_neg_integer(), binary()}],
          signature: binary()
        }

  @doc "Capabilities advertising MLS 1.0, ciphersuite 2 and basic credentials only."
  def default_capabilities do
    %{
      versions: [1],
      cipher_suites: [Crypto.cipher_suite()],
      extensions: [],
      proposals: [],
      credentials: [1]
    }
  end

  @doc "A lifetime that never expires, as DAVE requires."
  def unlimited_lifetime, do: {:key_package, 0, 0xFFFFFFFFFFFFFFFF}

  @doc """
  Signs the leaf. Leaves created for an Update or a Commit are bound to the
  group and to their position in it, key package leaves are not.
  """
  @spec sign(t(), binary(), binary() | nil, non_neg_integer() | nil) :: t()
  def sign(leaf, signature_private_key, group_id \\ nil, leaf_index \\ nil) do
    tbs = encode_tbs(leaf, group_id, leaf_index)
    %{leaf | signature: Crypto.sign_with_label(signature_private_key, "LeafNodeTBS", tbs)}
  end

  @spec verify(t(), binary() | nil, non_neg_integer() | nil) :: boolean()
  def verify(leaf, group_id \\ nil, leaf_index \\ nil) do
    tbs = encode_tbs(leaf, group_id, leaf_index)
    Crypto.verify_with_label(leaf.signature_key, "LeafNodeTBS", tbs, leaf.signature)
  end

  @spec encode(t()) :: iodata()
  def encode(leaf), do: [encode_content(leaf), Codec.vector(leaf.signature)]

  defp encode_tbs(%{source: {:key_package, _, _}} = leaf, _group_id, _leaf_index),
    do: encode_content(leaf)

  defp encode_tbs(leaf, group_id, leaf_index),
    do: [encode_content(leaf), Codec.vector(group_id), <<leaf_index::32>>]

  defp encode_content(leaf) do
    [
      Codec.vector(leaf.encryption_key),
      Codec.vector(leaf.signature_key),
      encode_credential(leaf.credential),
      encode_capabilities(leaf.capabilities),
      encode_source(leaf.source),
      Codec.extensions(leaf.extensions)
    ]
  end

  @spec encode_credential(credential()) :: iodata()
  def encode_credential({:basic, identity}), do: [<<1::16>>, Codec.vector(identity)]

  def encode_credential({:x509, certificates}),
    do: [<<2::16>>, Codec.list(certificates, &Codec.vector/1)]

  defp encode_capabilities(capabilities) do
    [
      Codec.uint16_list(capabilities.versions),
      Codec.uint16_list(capabilities.cipher_suites),
      Codec.uint16_list(capabilities.extensions),
      Codec.uint16_list(capabilities.proposals),
      Codec.uint16_list(capabilities.credentials)
    ]
  end

  defp encode_source({:key_package, not_before, not_after}),
    do: <<1, not_before::64, not_after::64>>

  defp encode_source(:update), do: <<2>>
  defp encode_source({:commit, parent_hash}), do: [<<3>>, Codec.vector(parent_hash)]

  @spec decode(binary()) :: {t(), binary()}
  def decode(binary) do
    {encryption_key, rest} = Codec.decode_vector(binary)
    {signature_key, rest} = Codec.decode_vector(rest)
    {credential, rest} = decode_credential(rest)
    {capabilities, rest} = decode_capabilities(rest)
    {source, rest} = decode_source(rest)
    {extensions, rest} = Codec.decode_extensions(rest)
    {signature, rest} = Codec.decode_vector(rest)

    leaf = %__MODULE__{
      encryption_key: encryption_key,
      signature_key: signature_key,
      credential: credential,
      capabilities: capabilities,
      source: source,
      extensions: extensions,
      signature: signature
    }

    {leaf, rest}
  end

  @spec decode_credential(binary()) :: {credential(), binary()}
  def decode_credential(<<1::16, rest::binary>>) do
    {identity, rest} = Codec.decode_vector(rest)
    {{:basic, identity}, rest}
  end

  def decode_credential(<<2::16, rest::binary>>) do
    {certificates, rest} = Codec.decode_list(rest, &Codec.decode_vector/1)
    {{:x509, certificates}, rest}
  end

  def decode_credential(_binary), do: raise(ArgumentError, "unsupported credential type")

  defp decode_capabilities(binary) do
    {versions, rest} = Codec.decode_uint16_list(binary)
    {cipher_suites, rest} = Codec.decode_uint16_list(rest)
    {extensions, rest} = Codec.decode_uint16_list(rest)
    {proposals, rest} = Codec.decode_uint16_list(rest)
    {credentials, rest} = Codec.decode_uint16_list(rest)

    capabilities = %{
      versions: versions,
      cipher_suites: cipher_suites,
      extensions: extensions,
      proposals: proposals,
      credentials: credentials
    }

    {capabilities, rest}
  end

  defp decode_source(<<1, not_before::64, not_after::64, rest::binary>>),
    do: {{:key_package, not_before, not_after}, rest}

  defp decode_source(<<2, rest::binary>>), do: {:update, rest}

  defp decode_source(<<3, rest::binary>>) do
    {parent_hash, rest} = Codec.decode_vector(rest)
    {{:commit, parent_hash}, rest}
  end

  defp decode_source(_binary), do: raise(ArgumentError, "invalid leaf node source")
end
