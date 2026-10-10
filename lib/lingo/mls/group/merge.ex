defmodule Lingo.MLS.Group.Merge do
  @moduledoc false

  # Merging a committer's UpdatePath into the tree and decrypting the path
  # secret meant for us (RFC 9420, section 7.5).

  alias Lingo.MLS.{Crypto, KeySchedule, LeafNode, Tree, TreeMath}

  alias Lingo.MLS.Group
  alias Lingo.MLS.Group.{Path, Util}

  def merge_path(_group, tree, nil, _committer, _added), do: {:ok, tree, KeySchedule.zero(), %{}}

  def merge_path(group, tree, path, committer, added),
    do: merge_update_path(group, tree, path, committer, added)

  @spec merge_update_path(Group.t(), Tree.t(), map(), non_neg_integer(), list()) ::
          {:ok, Tree.t(), binary(), map()} | {:error, atom()}
  def merge_update_path(group, tree, path, committer, added) do
    leaf = path.leaf_node
    public_keys = Enum.map(path.nodes, & &1.encryption_key)
    filtered = Tree.filtered_direct_path(tree, committer)
    tree_keys = MapSet.new(tree.nodes, fn {_x, node} -> node.encryption_key end)

    with :ok <- Util.check(match?({:commit, _}, leaf.source), :invalid_leaf_source),
         :ok <-
           Util.check(LeafNode.verify(leaf, group.group_id, committer), :invalid_leaf_signature),
         :ok <-
           Util.check(
             leaf.encryption_key != Tree.leaf(tree, committer).encryption_key,
             :reused_leaf_key
           ),
         :ok <- Util.check(length(public_keys) == length(filtered), :invalid_path_length),
         :ok <-
           Util.check(
             Enum.all?([leaf.encryption_key | public_keys], &(not MapSet.member?(tree_keys, &1))),
             :reused_key
           ) do
      {tree, parent_hash} = Tree.apply_path(tree, committer, public_keys)

      with :ok <- Util.check(leaf.source == {:commit, parent_hash}, :invalid_parent_hash) do
        tree = Tree.set_leaf(tree, committer, leaf)

        provisional =
          Util.encode_context(%{
            Group.context(group)
            | epoch: group.epoch + 1,
              tree_hash: Tree.tree_hash(tree)
          })

        decrypt_path(group, tree, path, filtered, provisional, added)
      end
    end
  end

  # finds the path node whose copath subtree holds us, decrypts its path secret
  # with a key we hold, and derives everything above it
  def decrypt_path(group, tree, path, filtered, provisional, added) do
    me = TreeMath.leaf_to_node(group.leaf_index)

    new_members =
      Enum.map(added, fn {leaf_index, _key_package} -> TreeMath.leaf_to_node(leaf_index) end)

    with {:ok, position} <-
           Util.fetch(
             Enum.find_index(filtered, fn {_x, copath} -> TreeMath.in_subtree?(me, copath) end),
             :not_in_path
           ),
         {_x, copath} = Enum.at(filtered, position),
         resolution = Tree.resolution(tree, copath) -- new_members,
         ciphertexts = Enum.at(path.nodes, position).ciphertexts,
         :ok <- Util.check(length(ciphertexts) == length(resolution), :invalid_path_length),
         {:ok, index, private_key} <- find_private_key(group, tree, resolution),
         {kem_output, ciphertext} = Enum.at(ciphertexts, index),
         {:ok, path_secret} <-
           Crypto.decrypt_with_label(
             private_key,
             "UpdatePathNode",
             provisional,
             kem_output,
             ciphertext
           )
           |> Util.or_error(:decryption_failed) do
      nodes = filtered |> Enum.drop(position) |> Enum.map(&elem(&1, 0))
      {keys, commit_secret} = Path.derive_path(nodes, path_secret)

      if Enum.all?(keys, fn {x, {public_key, _}} ->
           Tree.get(tree, x).encryption_key == public_key
         end),
         do: {:ok, tree, commit_secret, Map.new(keys)},
         else: {:error, :path_key_mismatch}
    end
  end

  def find_private_key(group, tree, resolution) do
    resolution
    |> Enum.with_index()
    |> Enum.find_value({:error, :no_private_key}, fn {x, index} ->
      with {public_key, private_key} <- group.private_keys[x],
           %{encryption_key: ^public_key} <- Tree.get(tree, x) do
        {:ok, index, private_key}
      else
        _missing -> nil
      end
    end)
  end
end
