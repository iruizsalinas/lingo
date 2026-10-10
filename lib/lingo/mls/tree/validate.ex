defmodule Lingo.MLS.Tree.Validate do
  @moduledoc false

  # Checks a ratchet tree received from someone else (RFC 9420, sections
  # 7.3, 7.9.2 and 12.4.3.1).

  alias Lingo.MLS.{LeafNode, ParentNode, Tree, TreeMath}
  alias Lingo.MLS.Tree.Hash

  @doc "Checks a whole tree received from someone else."
  @spec validate(Tree.t(), binary()) :: :ok | {:error, atom()}
  def validate(tree, group_id) do
    cond do
      not Enum.all?(Tree.leaves(tree), fn {index, leaf} -> valid_leaf?(leaf, group_id, index) end) ->
        {:error, :invalid_leaf}

      not unique_keys?(tree) ->
        {:error, :duplicate_keys}

      not valid_unmerged_leaves?(tree) ->
        {:error, :invalid_unmerged_leaves}

      not parent_hashes_valid?(tree) ->
        {:error, :invalid_parent_hash}

      true ->
        :ok
    end
  end

  def valid_leaf?(%LeafNode{source: {:key_package, _, _}} = leaf, _group_id, _index),
    do: LeafNode.verify(leaf)

  def valid_leaf?(leaf, group_id, index), do: LeafNode.verify(leaf, group_id, index)

  def unique_keys?(tree) do
    encryption_keys = Enum.map(tree.nodes, fn {_x, node} -> node.encryption_key end)
    signature_keys = Enum.map(Tree.leaves(tree), fn {_index, leaf} -> leaf.signature_key end)
    unique?(encryption_keys) and unique?(signature_keys)
  end

  def unique?(list), do: length(Enum.uniq(list)) == length(list)

  def valid_unmerged_leaves?(tree) do
    Enum.all?(parents(tree), fn {x, node} ->
      Enum.all?(node.unmerged_leaves, fn leaf_index ->
        leaf_x = TreeMath.leaf_to_node(leaf_index)

        Tree.leaf(tree, leaf_index) != nil and TreeMath.in_subtree?(leaf_x, x) and
          leaf_x
          |> TreeMath.direct_path(tree.leaf_count)
          |> Enum.take_while(&(&1 != x))
          |> Enum.all?(fn between ->
            case Tree.get(tree, between) do
              nil -> true
              node -> leaf_index in node.unmerged_leaves
            end
          end)
      end)
    end)
  end

  # top down: every non-blank parent must be parent-hash valid for exactly one descendant
  def parent_hashes_valid?(tree) do
    Enum.all?(parents(tree), fn {x, node} ->
      left = TreeMath.left(x)
      right = TreeMath.right(x)
      valid_children(tree, x, node, left, right) + valid_children(tree, x, node, right, left) == 1
    end)
  end

  def valid_children(tree, _x, node, child, sibling) do
    expected = Hash.parent_hash(node, original_tree_hash(tree, sibling, node.unmerged_leaves))
    resolution = Tree.resolution(tree, child)

    unmerged_below =
      node.unmerged_leaves
      |> Enum.map(&TreeMath.leaf_to_node/1)
      |> Enum.filter(&TreeMath.in_subtree?(&1, child))
      |> Enum.sort()

    Enum.count(resolution, fn d ->
      stored_parent_hash(Tree.get(tree, d)) == expected and
        Enum.sort(List.delete(resolution, d)) == unmerged_below
    end)
  end

  def stored_parent_hash(%ParentNode{parent_hash: parent_hash}), do: parent_hash
  def stored_parent_hash(%LeafNode{source: {:commit, parent_hash}}), do: parent_hash
  def stored_parent_hash(_leaf), do: nil

  # the tree hash of `x` as it was when the parent was last set: with the
  # parent's unmerged leaves blanked and dropped from every unmerged list
  def original_tree_hash(tree, x, []), do: Hash.tree_hash(tree, x)

  def original_tree_hash(tree, x, unmerged_leaves) do
    nodes =
      tree.nodes
      |> Map.drop(Enum.map(unmerged_leaves, &TreeMath.leaf_to_node/1))
      |> Map.new(fn
        {x, %ParentNode{} = node} ->
          {x, %{node | unmerged_leaves: node.unmerged_leaves -- unmerged_leaves}}

        entry ->
          entry
      end)

    Hash.tree_hash(%{tree | nodes: nodes}, x)
  end

  def parents(tree),
    do: Enum.filter(tree.nodes, fn {_x, node} -> match?(%ParentNode{}, node) end)
end
