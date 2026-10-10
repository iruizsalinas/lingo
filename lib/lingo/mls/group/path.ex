defmodule Lingo.MLS.Group.Path do
  @moduledoc false

  # Update paths: creating our own, and merging and decrypting a committer's (RFC 9420, section 7.5).

  alias Lingo.MLS.{Crypto, HPKE, LeafNode, Tree, TreeMath}

  alias Lingo.MLS.Group
  alias Lingo.MLS.Group.Util

  # derives key pairs along `nodes` from the first path secret and checks them
  # against the tree; returns the keys and the commit secret
  def derive_path_keys(tree, nodes, path_secret) do
    {keys, _commit_secret} = derive_path(nodes, path_secret)

    if Enum.all?(keys, fn {x, {public_key, _private_key}} ->
         Tree.get(tree, x).encryption_key == public_key
       end),
       do: {:ok, Map.new(keys)},
       else: {:error, :path_key_mismatch}
  end

  def derive_path(nodes, path_secret) do
    Enum.map_reduce(nodes, path_secret, fn x, path_secret ->
      key_pair = HPKE.derive_key_pair(Crypto.derive_secret(path_secret, "node"))
      {{x, key_pair}, Crypto.derive_secret(path_secret, "path")}
    end)
  end

  def create_path(group, tree, added) do
    me = group.leaf_index
    leaf_secret = Crypto.random()

    {leaf_public_key, leaf_private_key} =
      HPKE.derive_key_pair(Crypto.derive_secret(leaf_secret, "node"))

    filtered = Tree.filtered_direct_path(tree, me)

    {path_secrets, commit_secret} =
      Enum.map_reduce(filtered, Crypto.derive_secret(leaf_secret, "path"), fn {x, _copath},
                                                                              path_secret ->
        {{x, path_secret}, Crypto.derive_secret(path_secret, "path")}
      end)

    key_pairs =
      Map.new(path_secrets, fn {x, path_secret} ->
        {x, HPKE.derive_key_pair(Crypto.derive_secret(path_secret, "node"))}
      end)

    public_keys = Enum.map(filtered, fn {x, _copath} -> elem(key_pairs[x], 0) end)
    {tree, parent_hash} = Tree.apply_path(tree, me, public_keys)

    leaf =
      %{
        Tree.leaf(group.tree, me)
        | encryption_key: leaf_public_key,
          source: {:commit, parent_hash}
      }
      |> LeafNode.sign(group.signature_private_key, group.group_id, me)

    tree = Tree.set_leaf(tree, me, leaf)

    provisional =
      Util.encode_context(%{
        Group.context(group)
        | epoch: group.epoch + 1,
          tree_hash: Tree.tree_hash(tree)
      })

    new_members =
      Enum.map(added, fn {leaf_index, _key_package} -> TreeMath.leaf_to_node(leaf_index) end)

    nodes =
      for {{x, copath}, {x, path_secret}} <- Enum.zip(filtered, path_secrets) do
        ciphertexts =
          (Tree.resolution(tree, copath) -- new_members)
          |> Enum.map(fn r ->
            Crypto.encrypt_with_label(
              Tree.get(tree, r).encryption_key,
              "UpdatePathNode",
              provisional,
              path_secret
            )
          end)

        %{encryption_key: elem(key_pairs[x], 0), ciphertexts: ciphertexts}
      end

    keys = Map.put(key_pairs, TreeMath.leaf_to_node(me), {leaf_public_key, leaf_private_key})
    {tree, %{leaf_node: leaf, nodes: nodes}, Map.new(path_secrets), commit_secret, keys}
  end

  # the committer sent the path secret of our lowest common ancestor; the keys
  # above it follow from the committer's filtered direct path
  def welcome_path_keys(_tree, _leaf_index, _signer, nil), do: {:ok, %{}}

  def welcome_path_keys(tree, leaf_index, signer, path_secret) do
    ancestor =
      TreeMath.common_ancestor(TreeMath.leaf_to_node(leaf_index), TreeMath.leaf_to_node(signer))

    case Enum.drop_while(Tree.filtered_direct_path(tree, signer), fn {x, _copath} ->
           x != ancestor
         end) do
      [] -> {:error, :invalid_path_secret}
      nodes -> derive_path_keys(tree, Enum.map(nodes, &elem(&1, 0)), path_secret)
    end
  end
end
