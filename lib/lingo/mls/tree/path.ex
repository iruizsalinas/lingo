defmodule Lingo.MLS.Tree.Path do
  @moduledoc false

  # Resolutions and direct paths, and writing new path keys along one
  # (RFC 9420, sections 4.1 and 7.5).

  alias Lingo.MLS.{LeafNode, ParentNode, Tree, TreeMath}
  alias Lingo.MLS.Tree.Hash

  @doc "The resolution of `x`: the minimal set of non-blank nodes covering its subtree."
  @spec resolution(Tree.t(), non_neg_integer()) :: [non_neg_integer()]
  def resolution(tree, x) do
    case Tree.get(tree, x) do
      %ParentNode{unmerged_leaves: unmerged} -> [x | Enum.map(unmerged, &TreeMath.leaf_to_node/1)]
      %LeafNode{} -> [x]
      nil when rem(x, 2) == 0 -> []
      nil -> resolution(tree, TreeMath.left(x)) ++ resolution(tree, TreeMath.right(x))
    end
  end

  @spec filtered_direct_path(Tree.t(), non_neg_integer()) :: [
          {non_neg_integer(), non_neg_integer()}
        ]
  def filtered_direct_path(tree, leaf_index) do
    x = TreeMath.leaf_to_node(leaf_index)

    TreeMath.direct_path(x, tree.leaf_count)
    |> Enum.zip(TreeMath.copath(x, tree.leaf_count))
    |> Enum.reject(fn {_node, copath_child} -> resolution(tree, copath_child) == [] end)
  end

  @spec apply_path(Tree.t(), non_neg_integer(), [binary()]) :: {Tree.t(), binary()}
  def apply_path(tree, leaf_index, public_keys) do
    filtered = filtered_direct_path(tree, leaf_index)
    if length(filtered) != length(public_keys), do: raise(ArgumentError, "path length mismatch")

    tree = Tree.blank_direct_path(tree, leaf_index)

    tree =
      filtered
      |> Enum.zip(public_keys)
      |> Enum.reduce(tree, fn {{x, _copath_child}, key}, tree ->
        Tree.put(tree, x, %ParentNode{encryption_key: key})
      end)

    # parent hashes chain from the root down to the leaf
    filtered
    |> Enum.reverse()
    |> Enum.reduce({tree, <<>>}, fn {x, copath_child}, {tree, parent_hash} ->
      node = %{Tree.get(tree, x) | parent_hash: parent_hash}
      {Tree.put(tree, x, node), Hash.parent_hash(node, Hash.tree_hash(tree, copath_child))}
    end)
  end
end
