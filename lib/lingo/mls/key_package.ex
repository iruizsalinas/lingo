defmodule Lingo.MLS.KeyPackage do
  @moduledoc false

  # A signed, single-use offer to join a group (RFC 9420, section 10).

  alias Lingo.MLS.{Codec, Crypto, LeafNode}

  @enforce_keys [:init_key, :leaf_node]
  defstruct [:init_key, :leaf_node, version: 1, cipher_suite: 2, extensions: [], signature: <<>>]

  @type t :: %__MODULE__{
          version: non_neg_integer(),
          cipher_suite: non_neg_integer(),
          init_key: binary(),
          leaf_node: LeafNode.t(),
          extensions: [{non_neg_integer(), binary()}],
          signature: binary()
        }

  @spec sign(t(), binary()) :: t()
  def sign(key_package, signature_private_key) do
    signature =
      Crypto.sign_with_label(signature_private_key, "KeyPackageTBS", encode_tbs(key_package))

    %{key_package | signature: signature}
  end

  @doc "Validates a key package offered for an Add (RFC 9420, sections 10.1 and 12.1.1)."
  @spec validate(t()) :: :ok | {:error, atom()}
  def validate(key_package) do
    leaf = key_package.leaf_node

    cond do
      key_package.version != 1 or key_package.cipher_suite != Crypto.cipher_suite() ->
        {:error, :unsupported_key_package}

      not match?({:key_package, _, _}, leaf.source) ->
        {:error, :invalid_leaf_source}

      key_package.init_key == leaf.encryption_key ->
        {:error, :reused_init_key}

      not LeafNode.verify(leaf) ->
        {:error, :invalid_leaf_signature}

      not Crypto.verify_with_label(
        leaf.signature_key,
        "KeyPackageTBS",
        encode_tbs(key_package),
        key_package.signature
      ) ->
        {:error, :invalid_key_package_signature}

      true ->
        :ok
    end
  end

  @spec ref(t()) :: binary()
  def ref(key_package), do: Crypto.ref_hash("MLS 1.0 KeyPackage Reference", encode(key_package))

  @spec encode(t()) :: iodata()
  def encode(key_package), do: [encode_tbs(key_package), Codec.vector(key_package.signature)]

  defp encode_tbs(key_package) do
    [
      <<key_package.version::16, key_package.cipher_suite::16>>,
      Codec.vector(key_package.init_key),
      LeafNode.encode(key_package.leaf_node),
      Codec.extensions(key_package.extensions)
    ]
  end

  @spec decode(binary()) :: {t(), binary()}
  def decode(<<version::16, cipher_suite::16, rest::binary>>) do
    {init_key, rest} = Codec.decode_vector(rest)
    {leaf_node, rest} = LeafNode.decode(rest)
    {extensions, rest} = Codec.decode_extensions(rest)
    {signature, rest} = Codec.decode_vector(rest)

    key_package = %__MODULE__{
      version: version,
      cipher_suite: cipher_suite,
      init_key: init_key,
      leaf_node: leaf_node,
      extensions: extensions,
      signature: signature
    }

    {key_package, rest}
  end

  def decode(_binary), do: raise(ArgumentError, "truncated key package")
end
