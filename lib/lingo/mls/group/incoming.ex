defmodule Lingo.MLS.Group.Incoming do
  @moduledoc false

  # Handling proposals and commits from others, and authenticating their messages.

  alias Lingo.MLS.{Crypto, Framing, KeyPackage, LeafNode, Tree}

  alias Lingo.MLS.Group
  alias Lingo.MLS.Group.{Auth, Epoch, Merge, Util}

  @spec handle_proposal(Group.t(), binary()) :: {:ok, Group.t(), map()} | {:error, atom()}
  def handle_proposal(group, mls_message) do
    with {:ok, message} <- Auth.decode_public_message(mls_message),
         {:ok, proposal} <- Auth.fetch_content(message, :proposal),
         :ok <- Util.check(message.content.epoch == group.epoch, :wrong_epoch),
         :ok <- Auth.verify_message(group, message),
         :ok <- validate_proposal(group, proposal, message.content.sender) do
      ref = Crypto.ref_hash("MLS 1.0 Proposal Reference", Framing.authenticated_content(message))
      entry = %{ref: ref, proposal: proposal, sender: message.content.sender}
      {:ok, %{group | proposals: group.proposals ++ [entry]}, entry}
    end
  end

  @spec revoke(Group.t(), [binary()]) :: {:ok, Group.t()} | {:error, :unknown_proposal}
  def revoke(group, refs) do
    known = MapSet.new(group.proposals, & &1.ref)

    if Enum.all?(refs, &MapSet.member?(known, &1)),
      do: {:ok, %{group | proposals: Enum.reject(group.proposals, &(&1.ref in refs))}},
      else: {:error, :unknown_proposal}
  end

  def validate_proposal(_group, {:add, key_package}, _sender),
    do: KeyPackage.validate(key_package)

  def validate_proposal(group, {:remove, leaf_index}, _sender),
    do: Util.check(Tree.leaf(group.tree, leaf_index) != nil, :invalid_remove)

  def validate_proposal(group, {:update, leaf}, {:member, leaf_index}) do
    Util.check(
      leaf.source == :update and LeafNode.verify(leaf, group.group_id, leaf_index),
      :invalid_update
    )
  end

  def validate_proposal(_group, _proposal, _sender), do: {:error, :invalid_proposal}

  @spec handle_commit(Group.t(), binary(), Group.t() | nil) :: {:ok, Group.t()} | {:error, atom()}
  def handle_commit(group, mls_message, cached \\ nil) do
    with {:ok, message} <- Auth.decode_public_message(mls_message),
         {:ok, commit} <- Auth.fetch_content(message, :commit),
         :ok <- Util.check(message.content.epoch == group.epoch, :wrong_epoch),
         {:member, committer} <- message.content.sender,
         :ok <- Auth.verify_message(group, message) do
      cond do
        committer != group.leaf_index -> apply_commit(group, message, commit, committer)
        cached -> {:ok, cached}
        true -> {:error, :own_commit_without_state}
      end
    else
      {:error, reason} -> {:error, reason}
      _sender -> {:error, :invalid_sender}
    end
  end

  def apply_commit(group, message, commit, committer) do
    with {:ok, proposals} <- resolve_proposals(group, commit.proposals, committer),
         :ok <-
           Util.check(
             {:remove, group.leaf_index} not in Enum.map(proposals, &elem(&1, 0)),
             :removed
           ),
         :ok <-
           Util.check(commit.path != nil or not Epoch.path_required?(proposals), :missing_path),
         {:ok, tree, added} <- Epoch.apply_proposals(group, proposals, committer),
         {:ok, tree, commit_secret, keys} <-
           Merge.merge_path(group, tree, commit.path, committer, added) do
      {next, confirmation_tag} = Epoch.advance(group, tree, message, commit_secret)

      if Util.equal?(confirmation_tag, message.confirmation_tag) do
        {:ok, %{next | private_keys: Util.prune_keys(Map.merge(group.private_keys, keys), tree)}}
      else
        {:error, :invalid_confirmation_tag}
      end
    end
  end

  def resolve_proposals(group, items, committer) do
    Enum.reduce_while(items, {:ok, []}, fn
      {:reference, ref}, {:ok, acc} ->
        case Enum.find(group.proposals, &(&1.ref == ref)) do
          nil -> {:halt, {:error, :unknown_proposal}}
          entry -> {:cont, {:ok, [{entry.proposal, entry.sender} | acc]}}
        end

      {:proposal, proposal}, {:ok, acc} ->
        case validate_proposal(group, proposal, {:member, committer}) do
          :ok -> {:cont, {:ok, [{proposal, {:member, committer}} | acc]}}
          error -> {:halt, error}
        end
    end)
    |> case do
      {:ok, proposals} -> {:ok, Enum.reverse(proposals)}
      error -> error
    end
  end
end
