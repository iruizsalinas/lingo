defmodule Lingo.MLS.LeafNode do
  @moduledoc false

  # A member's leaf in the ratchet tree (RFC 9420, section 7.2).

  alias Lingo.MLS.Crypto
  alias Lingo.MLS.LeafNode.Wire

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
    tbs = Wire.encode_tbs(leaf, group_id, leaf_index)
    %{leaf | signature: Crypto.sign_with_label(signature_private_key, "LeafNodeTBS", tbs)}
  end

  @spec verify(t(), binary() | nil, non_neg_integer() | nil) :: boolean()
  def verify(leaf, group_id \\ nil, leaf_index \\ nil) do
    tbs = Wire.encode_tbs(leaf, group_id, leaf_index)
    Crypto.verify_with_label(leaf.signature_key, "LeafNodeTBS", tbs, leaf.signature)
  end

  defdelegate encode(leaf), to: Wire
  defdelegate decode(binary), to: Wire
  defdelegate encode_credential(credential), to: Wire
  defdelegate decode_credential(binary), to: Wire
end
