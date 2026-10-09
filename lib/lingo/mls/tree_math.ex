defmodule Lingo.MLS.TreeMath do
  @moduledoc false

  # Index arithmetic for the array representation of a complete binary tree
  # (RFC 9420, appendix C). Leaves sit at even indices, parent nodes at odd
  # ones, and the leaf count is always a power of two.

  import Bitwise

  @spec node_width(pos_integer()) :: pos_integer()
  def node_width(leaf_count), do: 2 * leaf_count - 1

  @spec root(pos_integer()) :: non_neg_integer()
  def root(leaf_count), do: (1 <<< log2(node_width(leaf_count))) - 1

  @spec level(non_neg_integer()) :: non_neg_integer()
  def level(x), do: trailing_ones(x, 0)

  defp trailing_ones(x, k) when (x >>> k &&& 1) == 1, do: trailing_ones(x, k + 1)
  defp trailing_ones(_x, k), do: k

  @spec leaf?(non_neg_integer()) :: boolean()
  def leaf?(x), do: rem(x, 2) == 0

  @spec leaf_to_node(non_neg_integer()) :: non_neg_integer()
  def leaf_to_node(leaf_index), do: 2 * leaf_index

  @spec node_to_leaf(non_neg_integer()) :: non_neg_integer()
  def node_to_leaf(x), do: div(x, 2)

  @spec left(non_neg_integer()) :: non_neg_integer()
  def left(x) do
    k = level(x)
    if k == 0, do: raise(ArgumentError, "leaf node has no children"), else: bxor(x, 1 <<< (k - 1))
  end

  @spec right(non_neg_integer()) :: non_neg_integer()
  def right(x) do
    k = level(x)
    if k == 0, do: raise(ArgumentError, "leaf node has no children"), else: bxor(x, 3 <<< (k - 1))
  end

  @spec parent(non_neg_integer(), pos_integer()) :: non_neg_integer()
  def parent(x, leaf_count) do
    if x == root(leaf_count), do: raise(ArgumentError, "root node has no parent")
    parent_within(parent_step(x), node_width(leaf_count))
  end

  defp parent_within(p, width) when p >= width, do: parent_within(parent_step(p), width)
  defp parent_within(p, _width), do: p

  defp parent_step(x) do
    k = level(x)
    b = x >>> (k + 1) &&& 1
    bxor(x ||| 1 <<< k, b <<< (k + 1))
  end

  @spec sibling(non_neg_integer(), pos_integer()) :: non_neg_integer()
  def sibling(x, leaf_count) do
    p = parent(x, leaf_count)
    if x < p, do: right(p), else: left(p)
  end

  @doc "The direct path of `x`, from its parent up to and including the root."
  @spec direct_path(non_neg_integer(), pos_integer()) :: [non_neg_integer()]
  def direct_path(x, leaf_count) do
    root = root(leaf_count)

    Stream.unfold(x, fn
      ^root -> nil
      node -> {parent(node, leaf_count), parent(node, leaf_count)}
    end)
    |> Enum.to_list()
  end

  @spec copath(non_neg_integer(), pos_integer()) :: [non_neg_integer()]
  def copath(x, leaf_count) do
    [x | direct_path(x, leaf_count)]
    |> Enum.drop(-1)
    |> Enum.map(&sibling(&1, leaf_count))
  end

  @doc "Whether `x` lies in the subtree rooted at `ancestor`, which spans 2^(level+1) - 1 nodes."
  @spec in_subtree?(non_neg_integer(), non_neg_integer()) :: boolean()
  def in_subtree?(x, ancestor) do
    half = (1 <<< level(ancestor)) - 1
    x >= ancestor - half and x <= ancestor + half
  end

  @spec common_ancestor(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def common_ancestor(x, y) do
    cond do
      in_subtree?(x, y) -> y
      in_subtree?(y, x) -> x
      true -> common_ancestor(x, y, 0)
    end
  end

  defp common_ancestor(x, y, k) when x >>> k == y >>> k,
    do: ((x >>> k) <<< k) + (1 <<< (k - 1)) - 1

  defp common_ancestor(x, y, k), do: common_ancestor(x, y, k + 1)

  defp log2(0), do: 0
  defp log2(x), do: log2(x, 0)
  defp log2(x, k) when x >>> (k + 1) > 0, do: log2(x, k + 1)
  defp log2(_x, k), do: k
end
