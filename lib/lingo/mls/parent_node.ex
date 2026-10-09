defmodule Lingo.MLS.ParentNode do
  @moduledoc false

  # An intermediate node of the ratchet tree (RFC 9420, section 7.1).

  alias Lingo.MLS.Codec

  @enforce_keys [:encryption_key]
  defstruct [:encryption_key, parent_hash: <<>>, unmerged_leaves: []]

  @type t :: %__MODULE__{
          encryption_key: binary(),
          parent_hash: binary(),
          unmerged_leaves: [non_neg_integer()]
        }

  @spec encode(t()) :: iodata()
  def encode(node) do
    [
      Codec.vector(node.encryption_key),
      Codec.vector(node.parent_hash),
      Codec.uint32_list(node.unmerged_leaves)
    ]
  end

  @spec decode(binary()) :: {t(), binary()}
  def decode(binary) do
    {encryption_key, rest} = Codec.decode_vector(binary)
    {parent_hash, rest} = Codec.decode_vector(rest)
    {unmerged_leaves, rest} = Codec.decode_uint32_list(rest)

    if unmerged_leaves != Enum.sort(Enum.uniq(unmerged_leaves)),
      do: raise(ArgumentError, "unmerged leaves must be sorted")

    node = %__MODULE__{
      encryption_key: encryption_key,
      parent_hash: parent_hash,
      unmerged_leaves: unmerged_leaves
    }

    {node, rest}
  end
end
