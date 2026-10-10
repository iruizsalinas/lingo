defmodule Lingo.MLS.Tree do
  @moduledoc false

  # The public half of a ratchet tree (RFC 9420, section 7): nodes, membership
  # changes, tree hashes and parent hashes. Private keys live in Lingo.MLS.Group.
  #
  # Nodes are kept in a map keyed by node index; a missing key is a blank node.

  alias Lingo.MLS.{LeafNode, ParentNode, TreeMath}
  alias Lingo.MLS.Tree.{Extension, Hash, Path, Validate}

  defstruct leaf_count: 1, nodes: %{}

  @type tree_node :: LeafNode.t() | ParentNode.t()
  @type t :: %__MODULE__{leaf_count: pos_integer(), nodes: %{non_neg_integer() => tree_node()}}

  @spec new(LeafNode.t()) :: t()
  def new(leaf), do: %__MODULE__{leaf_count: 1, nodes: %{0 => leaf}}

  @spec get(t(), non_neg_integer()) :: tree_node() | nil
  def get(tree, x), do: Map.get(tree.nodes, x)

  @spec leaf(t(), non_neg_integer()) :: LeafNode.t() | nil
  def leaf(tree, leaf_index), do: get(tree, TreeMath.leaf_to_node(leaf_index))

  @doc "The non-blank leaves as `{leaf_index, leaf}` pairs."
  @spec leaves(t()) :: [{non_neg_integer(), LeafNode.t()}]
  def leaves(tree) do
    for index <- 0..(tree.leaf_count - 1), leaf = leaf(tree, index), do: {index, leaf}
  end

  @doc false
  def put(tree, x, node), do: %{tree | nodes: Map.put(tree.nodes, x, node)}
  @doc false
  def blank(tree, x), do: %{tree | nodes: Map.delete(tree.nodes, x)}

  @doc false
  def direct_path(tree, leaf_index),
    do: TreeMath.direct_path(TreeMath.leaf_to_node(leaf_index), tree.leaf_count)

  ## Membership changes (RFC 9420, sections 7.7 and 12.1)

  @doc "Adds a leaf at the leftmost blank position, extending the tree if there is none."
  @spec add_leaf(t(), LeafNode.t()) :: {t(), non_neg_integer()}
  def add_leaf(tree, leaf) do
    {tree, index} =
      case Enum.find(0..(tree.leaf_count - 1), &(leaf(tree, &1) == nil)) do
        nil -> {%{tree | leaf_count: tree.leaf_count * 2}, tree.leaf_count}
        index -> {tree, index}
      end

    tree =
      tree
      |> direct_path(index)
      |> Enum.reduce(tree, fn x, tree ->
        case get(tree, x) do
          nil ->
            tree

          node ->
            put(tree, x, %{node | unmerged_leaves: Enum.sort([index | node.unmerged_leaves])})
        end
      end)

    {put(tree, TreeMath.leaf_to_node(index), leaf), index}
  end

  @doc "Sets a leaf without touching the rest of the tree, as merging an UpdatePath does."
  @spec set_leaf(t(), non_neg_integer(), LeafNode.t()) :: t()
  def set_leaf(tree, leaf_index, leaf), do: put(tree, TreeMath.leaf_to_node(leaf_index), leaf)

  @doc "Replaces a leaf and blanks its direct path."
  @spec update_leaf(t(), non_neg_integer(), LeafNode.t()) :: t()
  def update_leaf(tree, leaf_index, leaf) do
    tree
    |> blank_direct_path(leaf_index)
    |> put(TreeMath.leaf_to_node(leaf_index), leaf)
  end

  @spec remove_leaf(t(), non_neg_integer()) :: t()
  def remove_leaf(tree, leaf_index) do
    tree
    |> blank_direct_path(leaf_index)
    |> blank(TreeMath.leaf_to_node(leaf_index))
    |> truncate()
  end

  @doc false
  def blank_direct_path(tree, leaf_index),
    do: tree |> direct_path(leaf_index) |> Enum.reduce(tree, &blank(&2, &1))

  # drops the right half of the tree for as long as it holds no members
  defp truncate(%{leaf_count: leaf_count} = tree) when leaf_count > 1 do
    half = div(leaf_count, 2)

    if Enum.all?(half..(leaf_count - 1), &(leaf(tree, &1) == nil)) do
      nodes = Map.reject(tree.nodes, fn {x, _node} -> x >= leaf_count - 1 end)
      truncate(%{tree | leaf_count: half, nodes: nodes})
    else
      tree
    end
  end

  defp truncate(tree), do: tree

  ## Delegated to Tree.Hash, Tree.Validate, Tree.Extension and Tree.Path

  @doc "The tree hash of the whole tree, or of the subtree under node `x`."
  defdelegate tree_hash(tree), to: Hash
  defdelegate tree_hash(tree, x), to: Hash

  @doc "Checks a whole tree received from someone else."
  defdelegate validate(tree, group_id), to: Validate

  @doc "Encodes the tree for the ratchet_tree extension."
  defdelegate encode(tree), to: Extension

  @doc "Decodes a tree from the ratchet_tree extension."
  defdelegate decode(binary), to: Extension

  @doc "The resolution of `x`: the minimal set of non-blank nodes covering its subtree."
  defdelegate resolution(tree, x), to: Path

  @doc """
  The filtered direct path of a leaf as `{node, copath_child}` pairs from the
  bottom up, skipping nodes whose copath child has an empty resolution.
  """
  defdelegate filtered_direct_path(tree, leaf_index), to: Path

  @doc """
  Blanks the committer's direct path and installs the given public keys on its
  filtered direct path, then sets the parent hash chain. Returns the parent
  hash the committer's new leaf must carry (RFC 9420, sections 7.5 and 7.9).
  """
  defdelegate apply_path(tree, leaf_index, public_keys), to: Path
end
