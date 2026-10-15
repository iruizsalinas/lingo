defmodule Lingo.MLS.Group.Epoch do
  @moduledoc false

  # The steps every commit shares: applying proposals and advancing the key schedule.

  alias Lingo.MLS.{Crypto, Framing, KeySchedule, Tree}

  alias Lingo.MLS.Group
  alias Lingo.MLS.Group.Util

  # applies updates, then removes, then adds (RFC 9420, section 12.3)
  def apply_proposals(group, proposals, committer) do
    updates = for {{:update, leaf}, {:member, index}} <- proposals, do: {index, leaf}
    removes = for {{:remove, index}, _sender} <- proposals, do: index
    adds = for {{:add, key_package}, _sender} <- proposals, do: key_package

    signature_keys =
      group.tree
      |> Tree.leaves()
      |> Enum.reject(fn {index, _leaf} -> index in removes end)
      |> MapSet.new(fn {_index, leaf} -> leaf.signature_key end)

    added_signature_keys = Enum.map(adds, & &1.leaf_node.signature_key)

    cond do
      length(Enum.uniq(removes)) != length(removes) or committer in removes ->
        {:error, :invalid_remove}

      Enum.any?(removes, &(Tree.leaf(group.tree, &1) == nil)) ->
        {:error, :invalid_remove}

      length(Enum.uniq(added_signature_keys)) != length(added_signature_keys) or
          Enum.any?(added_signature_keys, &MapSet.member?(signature_keys, &1)) ->
        {:error, :duplicate_member}

      true ->
        tree =
          Enum.reduce(updates, group.tree, fn {index, leaf}, tree ->
            Tree.update_leaf(tree, index, leaf)
          end)

        tree = Enum.reduce(removes, tree, &Tree.remove_leaf(&2, &1))

        {added, tree} =
          Enum.map_reduce(adds, tree, fn key_package, tree ->
            {tree, index} = Tree.add_leaf(tree, key_package.leaf_node)
            {{index, key_package}, tree}
          end)

        {:ok, tree, added}
    end
  end

  def path_required?([]), do: true

  def path_required?(proposals),
    do:
      Enum.any?(proposals, fn {proposal, _sender} -> elem(proposal, 0) in [:update, :remove] end)

  # updates the transcript and key schedule for a commit; returns the next
  # group and the confirmation tag it implies
  def advance(group, tree, message, commit_secret) do
    confirmed =
      Crypto.hash([group.interim_transcript_hash, Framing.confirmed_transcript_input(message)])

    context = %{
      Group.context(group)
      | epoch: group.epoch + 1,
        tree_hash: Tree.tree_hash(tree),
        confirmed_transcript_hash: confirmed
    }

    secrets =
      KeySchedule.advance(group.secrets.init_secret, commit_secret, Util.encode_context(context))

    confirmation_tag = Crypto.mac(secrets.confirmation_key, confirmed)

    next = %{
      group
      | epoch: group.epoch + 1,
        tree: tree,
        secrets: secrets,
        confirmed_transcript_hash: confirmed,
        interim_transcript_hash: Util.interim_transcript_hash(confirmed, confirmation_tag),
        proposals: []
    }

    {next, confirmation_tag}
  end
end
