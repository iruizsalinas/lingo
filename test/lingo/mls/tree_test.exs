defmodule Lingo.MLS.TreeTest do
  use ExUnit.Case, async: true

  import Lingo.Test.MLSVectors

  alias Lingo.MLS.{Codec, Crypto, HPKE, KeyPackage, LeafNode, Tree, TreeMath}

  test "tree hashes, resolutions and validation" do
    for vector <- load("tree-validation") do
      tree = Codec.decode_exact(hex(vector["tree"]), &Tree.decode/1)

      assert IO.iodata_to_binary(Tree.encode(tree)) == hex(vector["tree"])
      assert Tree.validate(tree, hex(vector["group_id"])) == :ok

      for {expected, x} <- Enum.with_index(vector["tree_hashes"]) do
        assert Tree.tree_hash(tree, x) == hex(expected)
      end

      for {expected, x} <- Enum.with_index(vector["resolutions"]) do
        assert Tree.resolution(tree, x) == expected
      end
    end
  end

  test "rejects a tree whose leaf was tampered with" do
    [vector | _] = load("tree-validation")
    tree = Codec.decode_exact(hex(vector["tree"]), &Tree.decode/1)
    [{index, leaf} | _] = Tree.leaves(tree)

    tampered = %{
      tree
      | nodes: Map.put(tree.nodes, 2 * index, %{leaf | credential: {:basic, "mallory"}})
    }

    assert {:error, _reason} = Tree.validate(tampered, hex(vector["group_id"]))
  end

  describe "membership changes" do
    test "adds fill the leftmost blank leaf, removes truncate" do
      tree = Tree.new(leaf("a"))

      {tree, 1} = Tree.add_leaf(tree, leaf("b"))
      {tree, 2} = Tree.add_leaf(tree, leaf("c"))
      assert tree.leaf_count == 4

      tree = Tree.remove_leaf(tree, 1)
      assert tree.leaf_count == 4
      {tree, 1} = Tree.add_leaf(tree, leaf("d"))

      tree = tree |> Tree.remove_leaf(2) |> Tree.remove_leaf(1)
      assert tree.leaf_count == 1
      assert [{0, %LeafNode{credential: {:basic, "a"}}}] = Tree.leaves(tree)
    end

    test "new leaves are unmerged at every non-blank ancestor" do
      tree = Tree.new(leaf("a"))
      {tree, 1} = Tree.add_leaf(tree, leaf("b"))
      {tree, _parent_hash} = Tree.apply_path(tree, 0, [elem(HPKE.generate_key_pair(), 0)])

      {tree, 2} = Tree.add_leaf(tree, leaf("c"))
      assert Tree.get(tree, 1).unmerged_leaves == []
      assert Tree.resolution(tree, TreeMath.root(4)) == [1, 4]
    end
  end

  test "ratchet trees round trip" do
    tree = Tree.new(leaf("a"))
    {tree, _} = Tree.add_leaf(tree, leaf("b"))
    {tree, _} = Tree.add_leaf(tree, leaf("c"))

    encoded = IO.iodata_to_binary(Tree.encode(tree))
    decoded = Codec.decode_exact(encoded, &Tree.decode/1)

    assert decoded == tree
    assert Tree.tree_hash(decoded) == Tree.tree_hash(tree)
  end

  defp leaf(name) do
    {encryption_key, _} = HPKE.generate_key_pair()
    {signature_key, signature_private_key} = Crypto.generate_signature_key()

    %LeafNode{
      encryption_key: encryption_key,
      signature_key: signature_key,
      credential: {:basic, name},
      capabilities: LeafNode.default_capabilities(),
      source: LeafNode.unlimited_lifetime()
    }
    |> LeafNode.sign(signature_private_key)
  end

  test "key packages validate and reject tampering" do
    {init_key, _} = HPKE.generate_key_pair()
    {signature_key, signature_private_key} = Crypto.generate_signature_key()
    {encryption_key, _} = HPKE.generate_key_pair()

    leaf =
      %LeafNode{
        encryption_key: encryption_key,
        signature_key: signature_key,
        credential: {:basic, <<1::64>>},
        capabilities: LeafNode.default_capabilities(),
        source: LeafNode.unlimited_lifetime()
      }
      |> LeafNode.sign(signature_private_key)

    key_package =
      KeyPackage.sign(%KeyPackage{init_key: init_key, leaf_node: leaf}, signature_private_key)

    assert KeyPackage.validate(key_package) == :ok

    encoded = IO.iodata_to_binary(KeyPackage.encode(key_package))
    assert Codec.decode_exact(encoded, &KeyPackage.decode/1) == key_package

    assert {:error, :invalid_key_package_signature} =
             KeyPackage.validate(%{key_package | extensions: [{0xFF, "x"}]})

    assert {:error, :reused_init_key} =
             KeyPackage.validate(%{key_package | init_key: encryption_key})
  end
end
