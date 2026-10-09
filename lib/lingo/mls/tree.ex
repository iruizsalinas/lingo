defmodule Lingo.MLS.Tree do
  @moduledoc false

  # The public half of a ratchet tree (RFC 9420, section 7): nodes, membership
  # changes, tree hashes and parent hashes. Private keys live in Lingo.MLS.Group.
  #
  # Nodes are kept in a map keyed by node index; a missing key is a blank node.

  alias Lingo.MLS.{Codec, Crypto, LeafNode, ParentNode, TreeMath}

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

  defp put(tree, x, node), do: %{tree | nodes: Map.put(tree.nodes, x, node)}
  defp blank(tree, x), do: %{tree | nodes: Map.delete(tree.nodes, x)}

  defp direct_path(tree, leaf_index),
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

  defp blank_direct_path(tree, leaf_index),
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

  ## Paths (RFC 9420, section 4.1)

  @doc "The resolution of `x`: the minimal set of non-blank nodes covering its subtree."
  @spec resolution(t(), non_neg_integer()) :: [non_neg_integer()]
  def resolution(tree, x) do
    case get(tree, x) do
      %ParentNode{unmerged_leaves: unmerged} -> [x | Enum.map(unmerged, &TreeMath.leaf_to_node/1)]
      %LeafNode{} -> [x]
      nil when rem(x, 2) == 0 -> []
      nil -> resolution(tree, TreeMath.left(x)) ++ resolution(tree, TreeMath.right(x))
    end
  end

  @doc """
  The filtered direct path of a leaf as `{node, copath_child}` pairs from the
  bottom up, skipping nodes whose copath child has an empty resolution.
  """
  @spec filtered_direct_path(t(), non_neg_integer()) :: [{non_neg_integer(), non_neg_integer()}]
  def filtered_direct_path(tree, leaf_index) do
    x = TreeMath.leaf_to_node(leaf_index)

    TreeMath.direct_path(x, tree.leaf_count)
    |> Enum.zip(TreeMath.copath(x, tree.leaf_count))
    |> Enum.reject(fn {_node, copath_child} -> resolution(tree, copath_child) == [] end)
  end

  @doc """
  Blanks the committer's direct path and installs the given public keys on its
  filtered direct path, then sets the parent hash chain. Returns the parent
  hash the committer's new leaf must carry (RFC 9420, sections 7.5 and 7.9).
  """
  @spec apply_path(t(), non_neg_integer(), [binary()]) :: {t(), binary()}
  def apply_path(tree, leaf_index, public_keys) do
    filtered = filtered_direct_path(tree, leaf_index)
    if length(filtered) != length(public_keys), do: raise(ArgumentError, "path length mismatch")

    tree = blank_direct_path(tree, leaf_index)

    tree =
      filtered
      |> Enum.zip(public_keys)
      |> Enum.reduce(tree, fn {{x, _copath_child}, key}, tree ->
        put(tree, x, %ParentNode{encryption_key: key})
      end)

    # parent hashes chain from the root down to the leaf
    filtered
    |> Enum.reverse()
    |> Enum.reduce({tree, <<>>}, fn {x, copath_child}, {tree, parent_hash} ->
      node = %{get(tree, x) | parent_hash: parent_hash}
      {put(tree, x, node), parent_hash(node, tree_hash(tree, copath_child))}
    end)
  end

  ## Hashes (RFC 9420, sections 7.8 and 7.9)

  @spec tree_hash(t()) :: binary()
  def tree_hash(tree), do: tree_hash(tree, TreeMath.root(tree.leaf_count))

  @spec tree_hash(t(), non_neg_integer()) :: binary()
  def tree_hash(tree, x) do
    if TreeMath.leaf?(x) do
      Crypto.hash([
        <<1, TreeMath.node_to_leaf(x)::32>>,
        Codec.optional(get(tree, x), &LeafNode.encode/1)
      ])
    else
      Crypto.hash([
        <<2>>,
        Codec.optional(get(tree, x), &ParentNode.encode/1),
        Codec.vector(tree_hash(tree, TreeMath.left(x))),
        Codec.vector(tree_hash(tree, TreeMath.right(x)))
      ])
    end
  end

  defp parent_hash(node, sibling_tree_hash) do
    Crypto.hash([
      Codec.vector(node.encryption_key),
      Codec.vector(node.parent_hash),
      Codec.vector(sibling_tree_hash)
    ])
  end

  ## Validation (RFC 9420, sections 7.3, 7.9.2 and 12.4.3.1)

  @doc "Checks a whole tree received from someone else."
  @spec validate(t(), binary()) :: :ok | {:error, atom()}
  def validate(tree, group_id) do
    cond do
      not Enum.all?(leaves(tree), fn {index, leaf} -> valid_leaf?(leaf, group_id, index) end) ->
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

  defp valid_leaf?(%LeafNode{source: {:key_package, _, _}} = leaf, _group_id, _index),
    do: LeafNode.verify(leaf)

  defp valid_leaf?(leaf, group_id, index), do: LeafNode.verify(leaf, group_id, index)

  defp unique_keys?(tree) do
    encryption_keys = Enum.map(tree.nodes, fn {_x, node} -> node.encryption_key end)
    signature_keys = Enum.map(leaves(tree), fn {_index, leaf} -> leaf.signature_key end)
    unique?(encryption_keys) and unique?(signature_keys)
  end

  defp unique?(list), do: length(Enum.uniq(list)) == length(list)

  defp valid_unmerged_leaves?(tree) do
    Enum.all?(parents(tree), fn {x, node} ->
      Enum.all?(node.unmerged_leaves, fn leaf_index ->
        leaf_x = TreeMath.leaf_to_node(leaf_index)

        leaf(tree, leaf_index) != nil and TreeMath.in_subtree?(leaf_x, x) and
          leaf_x
          |> TreeMath.direct_path(tree.leaf_count)
          |> Enum.take_while(&(&1 != x))
          |> Enum.all?(fn between ->
            case get(tree, between) do
              nil -> true
              node -> leaf_index in node.unmerged_leaves
            end
          end)
      end)
    end)
  end

  # top down: every non-blank parent must be parent-hash valid for exactly one descendant
  defp parent_hashes_valid?(tree) do
    Enum.all?(parents(tree), fn {x, node} ->
      left = TreeMath.left(x)
      right = TreeMath.right(x)
      valid_children(tree, x, node, left, right) + valid_children(tree, x, node, right, left) == 1
    end)
  end

  defp valid_children(tree, _x, node, child, sibling) do
    expected = parent_hash(node, original_tree_hash(tree, sibling, node.unmerged_leaves))
    resolution = resolution(tree, child)

    unmerged_below =
      node.unmerged_leaves
      |> Enum.map(&TreeMath.leaf_to_node/1)
      |> Enum.filter(&TreeMath.in_subtree?(&1, child))
      |> Enum.sort()

    Enum.count(resolution, fn d ->
      stored_parent_hash(get(tree, d)) == expected and
        Enum.sort(List.delete(resolution, d)) == unmerged_below
    end)
  end

  defp stored_parent_hash(%ParentNode{parent_hash: parent_hash}), do: parent_hash
  defp stored_parent_hash(%LeafNode{source: {:commit, parent_hash}}), do: parent_hash
  defp stored_parent_hash(_leaf), do: nil

  # the tree hash of `x` as it was when the parent was last set: with the
  # parent's unmerged leaves blanked and dropped from every unmerged list
  defp original_tree_hash(tree, x, []), do: tree_hash(tree, x)

  defp original_tree_hash(tree, x, unmerged_leaves) do
    nodes =
      tree.nodes
      |> Map.drop(Enum.map(unmerged_leaves, &TreeMath.leaf_to_node/1))
      |> Map.new(fn
        {x, %ParentNode{} = node} ->
          {x, %{node | unmerged_leaves: node.unmerged_leaves -- unmerged_leaves}}

        entry ->
          entry
      end)

    tree_hash(%{tree | nodes: nodes}, x)
  end

  defp parents(tree),
    do: Enum.filter(tree.nodes, fn {_x, node} -> match?(%ParentNode{}, node) end)

  ## The ratchet_tree extension (RFC 9420, section 12.4.3.3)

  @spec encode(t()) :: iodata()
  def encode(tree) do
    last = tree.nodes |> Map.keys() |> Enum.max()
    Codec.list(Enum.to_list(0..last), fn x -> Codec.optional(get(tree, x), &encode_node/1) end)
  end

  defp encode_node(%LeafNode{} = leaf), do: [<<1>>, LeafNode.encode(leaf)]
  defp encode_node(%ParentNode{} = node), do: [<<2>>, ParentNode.encode(node)]

  @spec decode(binary()) :: {t(), binary()}
  def decode(binary) do
    {nodes, rest} =
      Codec.decode_list(binary, &Codec.decode_optional(&1, fn node -> decode_node(node) end))

    if nodes == [] or List.last(nodes) == nil, do: raise(ArgumentError, "invalid ratchet tree")

    nodes =
      for {node, x} <- Enum.with_index(nodes), node != nil, into: %{} do
        case {node, TreeMath.leaf?(x)} do
          {%LeafNode{}, true} -> {x, node}
          {%ParentNode{}, false} -> {x, node}
          _misplaced -> raise ArgumentError, "node type does not match its position"
        end
      end

    {%__MODULE__{leaf_count: leaf_count_for(length_of(nodes)), nodes: nodes}, rest}
  end

  defp decode_node(<<1, rest::binary>>), do: LeafNode.decode(rest)
  defp decode_node(<<2, rest::binary>>), do: ParentNode.decode(rest)
  defp decode_node(_binary), do: raise(ArgumentError, "invalid node type")

  defp length_of(nodes), do: (nodes |> Map.keys() |> Enum.max()) + 1

  defp leaf_count_for(width), do: leaf_count_for(width, 1)
  defp leaf_count_for(width, n) when 2 * n - 1 >= width, do: n
  defp leaf_count_for(width, n), do: leaf_count_for(width, n * 2)
end
