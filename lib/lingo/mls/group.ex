defmodule Lingo.MLS.Group do
  @moduledoc false

  # An MLS group seen by one member (RFC 9420): creating a group, joining from
  # a Welcome, queueing proposals, committing and processing commits.
  #
  # Every function is pure and returns a new group, so a caller can try an
  # operation and keep the old state if it fails, which DAVE relies on.

  alias Lingo.MLS.{Crypto, KeySchedule, LeafNode, Message, Tree, Welcome}

  @enforce_keys [:group_id, :tree, :leaf_index, :signature_private_key, :secrets]
  defstruct [
    :group_id,
    :tree,
    :leaf_index,
    :signature_private_key,
    :secrets,
    epoch: 0,
    extensions: [],
    confirmed_transcript_hash: <<>>,
    interim_transcript_hash: <<>>,
    # node index => {public key, private key}
    private_keys: %{},
    # [%{ref: binary, proposal: tuple, sender: tuple}] in arrival order
    proposals: []
  ]

  @type t :: %__MODULE__{}

  alias Lingo.MLS.Group.{Incoming, Join, Merge, Outgoing, Util}

  @doc "Creates a one-member group (RFC 9420, section 11)."
  @spec create(binary(), LeafNode.t(), binary(), binary(), list()) :: t()
  def create(group_id, leaf, encryption_private_key, signature_private_key, extensions \\ []) do
    secrets = KeySchedule.from_epoch_secret(Crypto.random())
    confirmation_tag = Crypto.mac(secrets.confirmation_key, <<>>)

    %__MODULE__{
      group_id: group_id,
      tree: Tree.new(leaf),
      leaf_index: 0,
      signature_private_key: signature_private_key,
      secrets: secrets,
      extensions: extensions,
      interim_transcript_hash: Util.interim_transcript_hash(<<>>, confirmation_tag),
      private_keys: %{0 => {leaf.encryption_key, encryption_private_key}}
    }
  end

  @doc """
  Joins a group from a Welcome (RFC 9420, section 12.4.3.1). The ratchet tree
  comes from the GroupInfo's ratchet_tree extension unless one is given.
  """
  defdelegate join(
                welcome,
                key_package,
                init_private_key,
                encryption_private_key,
                signature_private_key,
                ratchet_tree \\ nil
              ),
              to: Join

  @doc """
  Verifies and queues a proposal sent as an MLSMessage. Returns the queued
  entry, so the caller can apply its own policy before keeping the new group.
  """
  defdelegate handle_proposal(group, mls_message), to: Incoming

  @doc "Drops queued proposals by reference."
  defdelegate revoke(group, refs), to: Incoming

  @doc """
  Commits every queued proposal by reference (RFC 9420, section 12.4.1).
  Returns the Commit as an MLSMessage, a Welcome when members were added, and
  the group as it will be once the Commit is accepted.
  """
  defdelegate commit(group), to: Outgoing

  @doc """
  Processes a Commit sent as an MLSMessage (RFC 9420, section 12.4.2). Our own
  commits can't be decrypted, so `cached` must hold the state commit/1 returned.
  """
  defdelegate handle_commit(group, mls_message, cached \\ nil), to: Incoming

  @doc false
  defdelegate merge_update_path(group, tree, path, committer, added), to: Merge

  @spec external_senders(t()) :: [map()]
  def external_senders(group) do
    with {_type, data} <- List.keyfind(group.extensions, Message.extension_external_senders(), 0),
         {:ok, senders} <- Message.decode(data, &Welcome.decode_external_senders/1) do
      senders
    else
      _missing -> []
    end
  end

  @spec export(t(), String.t(), binary(), pos_integer()) :: binary()
  def export(group, label, context, length),
    do: KeySchedule.export(group.secrets.exporter_secret, label, context, length)

  @spec epoch_authenticator(t()) :: binary()
  def epoch_authenticator(group), do: group.secrets.epoch_authenticator

  @spec roster(t()) :: [{non_neg_integer(), LeafNode.t()}]
  def roster(group), do: Tree.leaves(group.tree)

  @spec context(t()) :: map()
  def context(group) do
    %{
      cipher_suite: Crypto.cipher_suite(),
      group_id: group.group_id,
      epoch: group.epoch,
      tree_hash: Tree.tree_hash(group.tree),
      confirmed_transcript_hash: group.confirmed_transcript_hash,
      extensions: group.extensions
    }
  end
end
