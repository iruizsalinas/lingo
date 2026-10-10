defmodule Lingo.MLS.LeafNode.Wire do
  @moduledoc false

  # LeafNode encoding (RFC 9420, section 7.2).

  alias Lingo.MLS.{Codec, LeafNode}

  @spec encode(LeafNode.t()) :: iodata()
  def encode(leaf), do: [encode_content(leaf), Codec.vector(leaf.signature)]

  def encode_tbs(%{source: {:key_package, _, _}} = leaf, _group_id, _leaf_index),
    do: encode_content(leaf)

  def encode_tbs(leaf, group_id, leaf_index),
    do: [encode_content(leaf), Codec.vector(group_id), <<leaf_index::32>>]

  def encode_content(leaf) do
    [
      Codec.vector(leaf.encryption_key),
      Codec.vector(leaf.signature_key),
      encode_credential(leaf.credential),
      encode_capabilities(leaf.capabilities),
      encode_source(leaf.source),
      Codec.extensions(leaf.extensions)
    ]
  end

  @spec encode_credential(LeafNode.credential()) :: iodata()
  def encode_credential({:basic, identity}), do: [<<1::16>>, Codec.vector(identity)]

  def encode_credential({:x509, certificates}),
    do: [<<2::16>>, Codec.list(certificates, &Codec.vector/1)]

  def encode_capabilities(capabilities) do
    [
      Codec.uint16_list(capabilities.versions),
      Codec.uint16_list(capabilities.cipher_suites),
      Codec.uint16_list(capabilities.extensions),
      Codec.uint16_list(capabilities.proposals),
      Codec.uint16_list(capabilities.credentials)
    ]
  end

  def encode_source({:key_package, not_before, not_after}),
    do: <<1, not_before::64, not_after::64>>

  def encode_source(:update), do: <<2>>
  def encode_source({:commit, parent_hash}), do: [<<3>>, Codec.vector(parent_hash)]

  @spec decode(binary()) :: {LeafNode.t(), binary()}
  def decode(binary) do
    {encryption_key, rest} = Codec.decode_vector(binary)
    {signature_key, rest} = Codec.decode_vector(rest)
    {credential, rest} = decode_credential(rest)
    {capabilities, rest} = decode_capabilities(rest)
    {source, rest} = decode_source(rest)
    {extensions, rest} = Codec.decode_extensions(rest)
    {signature, rest} = Codec.decode_vector(rest)

    leaf = %LeafNode{
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

  @spec decode_credential(binary()) :: {LeafNode.credential(), binary()}
  def decode_credential(<<1::16, rest::binary>>) do
    {identity, rest} = Codec.decode_vector(rest)
    {{:basic, identity}, rest}
  end

  def decode_credential(<<2::16, rest::binary>>) do
    {certificates, rest} = Codec.decode_list(rest, &Codec.decode_vector/1)
    {{:x509, certificates}, rest}
  end

  def decode_credential(_binary), do: raise(ArgumentError, "unsupported credential type")

  def decode_capabilities(binary) do
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

  def decode_source(<<1, not_before::64, not_after::64, rest::binary>>),
    do: {{:key_package, not_before, not_after}, rest}

  def decode_source(<<2, rest::binary>>), do: {:update, rest}

  def decode_source(<<3, rest::binary>>) do
    {parent_hash, rest} = Codec.decode_vector(rest)
    {{:commit, parent_hash}, rest}
  end

  def decode_source(_binary), do: raise(ArgumentError, "invalid leaf node source")
end
