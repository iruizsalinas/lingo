defmodule Lingo.MLS.Tree.Hash do
  @moduledoc false

  # Tree hashes and parent hashes (RFC 9420, sections 7.8 and 7.9).

  alias Lingo.MLS.{Codec, Crypto, LeafNode, ParentNode, Tree, TreeMath}

  @spec tree_hash(Tree.t()) :: binary()
  def tree_hash(tree), do: tree_hash(tree, TreeMath.root(tree.leaf_count))

  @spec tree_hash(Tree.t(), non_neg_integer()) :: binary()
  def tree_hash(tree, x) do
    if TreeMath.leaf?(x) do
      Crypto.hash([
        <<1, TreeMath.node_to_leaf(x)::32>>,
        Codec.optional(Tree.get(tree, x), &LeafNode.encode/1)
      ])
    else
      Crypto.hash([
        <<2>>,
        Codec.optional(Tree.get(tree, x), &ParentNode.encode/1),
        Codec.vector(tree_hash(tree, TreeMath.left(x))),
        Codec.vector(tree_hash(tree, TreeMath.right(x)))
      ])
    end
  end

  def parent_hash(node, sibling_tree_hash) do
    Crypto.hash([
      Codec.vector(node.encryption_key),
      Codec.vector(node.parent_hash),
      Codec.vector(sibling_tree_hash)
    ])
  end
end
