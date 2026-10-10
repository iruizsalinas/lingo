defmodule Lingo.MLS.Tree.Extension do
  @moduledoc false

  # The ratchet_tree extension: a whole tree on the wire (RFC 9420, section
  # 12.4.3.3).

  alias Lingo.MLS.{Codec, LeafNode, ParentNode, Tree, TreeMath}

  @spec encode(Tree.t()) :: iodata()
  def encode(tree) do
    last = tree.nodes |> Map.keys() |> Enum.max()

    Codec.list(Enum.to_list(0..last), fn x ->
      Codec.optional(Tree.get(tree, x), &encode_node/1)
    end)
  end

  def encode_node(%LeafNode{} = leaf), do: [<<1>>, LeafNode.encode(leaf)]
  def encode_node(%ParentNode{} = node), do: [<<2>>, ParentNode.encode(node)]

  @spec decode(binary()) :: {Tree.t(), binary()}
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

    {%Tree{leaf_count: leaf_count_for(length_of(nodes)), nodes: nodes}, rest}
  end

  def decode_node(<<1, rest::binary>>), do: LeafNode.decode(rest)
  def decode_node(<<2, rest::binary>>), do: ParentNode.decode(rest)
  def decode_node(_binary), do: raise(ArgumentError, "invalid node type")

  def length_of(nodes), do: (nodes |> Map.keys() |> Enum.max()) + 1

  def leaf_count_for(width), do: leaf_count_for(width, 1)
  def leaf_count_for(width, n) when 2 * n - 1 >= width, do: n
  def leaf_count_for(width, n), do: leaf_count_for(width, n * 2)
end
