defmodule Lingo.MLS.Group do
  @moduledoc false

  # An MLS group seen by one member (RFC 9420): creating a group, joining from
  # a Welcome, queueing proposals, committing and processing commits.
  #
  # Every function is pure and returns a new group, so a caller can try an
  # operation and keep the old state if it fails, which DAVE relies on.

  alias Lingo.MLS.{
    Codec,
    Crypto,
    HPKE,
    KeyPackage,
    KeySchedule,
    LeafNode,
    Message,
    Tree,
    TreeMath
  }

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

  ## Creating and joining

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
      interim_transcript_hash: interim_transcript_hash(<<>>, confirmation_tag),
      private_keys: %{0 => {leaf.encryption_key, encryption_private_key}}
    }
  end

  @doc """
  Joins a group from a Welcome (RFC 9420, section 12.4.3.1). The ratchet tree
  comes from the GroupInfo's ratchet_tree extension unless one is given.
  """
  @spec join(binary(), KeyPackage.t(), binary(), binary(), binary(), binary() | nil) ::
          {:ok, t()} | {:error, atom()}
  def join(
        welcome,
        key_package,
        init_private_key,
        encryption_private_key,
        signature_private_key,
        ratchet_tree \\ nil
      ) do
    ref = KeyPackage.ref(key_package)

    with {:ok, welcome} <- Message.decode(welcome, &Message.decode_welcome/1),
         :ok <- check(welcome.cipher_suite == Crypto.cipher_suite(), :unsupported_cipher_suite),
         {:ok, entry} <- fetch(Enum.find(welcome.secrets, &(&1.new_member == ref)), :not_for_us),
         {:ok, group_secrets} <- decrypt_group_secrets(welcome, entry, init_private_key),
         {:ok, group_info} <- decrypt_group_info(welcome, group_secrets.joiner_secret),
         context = group_info.group_context,
         :ok <- check(context.cipher_suite == Crypto.cipher_suite(), :unsupported_cipher_suite),
         {:ok, tree} <- welcome_tree(group_info, ratchet_tree),
         :ok <- check(Tree.tree_hash(tree) == context.tree_hash, :tree_hash_mismatch),
         :ok <- Tree.validate(tree, context.group_id),
         :ok <- verify_group_info(tree, group_info),
         {:ok, {leaf_index, leaf}} <- find_own_leaf(tree, key_package.leaf_node),
         :ok <-
           check(HPKE.public_key(encryption_private_key) == leaf.encryption_key, :key_mismatch),
         {:ok, path_keys} <-
           welcome_path_keys(tree, leaf_index, group_info.signer, group_secrets.path_secret) do
      secrets = KeySchedule.join(group_secrets.joiner_secret, encode_context(context))

      if equal?(
           Crypto.mac(secrets.confirmation_key, context.confirmed_transcript_hash),
           group_info.confirmation_tag
         ) do
        group = %__MODULE__{
          group_id: context.group_id,
          epoch: context.epoch,
          tree: tree,
          leaf_index: leaf_index,
          signature_private_key: signature_private_key,
          secrets: secrets,
          extensions: context.extensions,
          confirmed_transcript_hash: context.confirmed_transcript_hash,
          interim_transcript_hash:
            interim_transcript_hash(
              context.confirmed_transcript_hash,
              group_info.confirmation_tag
            ),
          private_keys:
            Map.put(
              path_keys,
              TreeMath.leaf_to_node(leaf_index),
              {leaf.encryption_key, encryption_private_key}
            )
        }

        {:ok, group}
      else
        {:error, :invalid_confirmation_tag}
      end
    end
  end

  defp decrypt_group_secrets(welcome, entry, init_private_key) do
    case Crypto.decrypt_with_label(
           init_private_key,
           "Welcome",
           welcome.encrypted_group_info,
           entry.kem_output,
           entry.ciphertext
         ) do
      {:ok, plaintext} -> Message.decode(plaintext, &Message.decode_group_secrets/1)
      :error -> {:error, :decryption_failed}
    end
  end

  defp decrypt_group_info(welcome, joiner_secret) do
    {key, nonce} = KeySchedule.welcome_key_and_nonce(KeySchedule.welcome_secret(joiner_secret))

    case Crypto.open(key, nonce, "", welcome.encrypted_group_info) do
      {:ok, plaintext} -> Message.decode(plaintext, &Message.decode_group_info/1)
      :error -> {:error, :decryption_failed}
    end
  end

  defp welcome_tree(group_info, nil) do
    case List.keyfind(group_info.extensions, Message.extension_ratchet_tree(), 0) do
      {_type, data} -> Message.decode(data, &Tree.decode/1)
      nil -> {:error, :missing_ratchet_tree}
    end
  end

  defp welcome_tree(_group_info, ratchet_tree), do: Message.decode(ratchet_tree, &Tree.decode/1)

  defp verify_group_info(tree, group_info) do
    case Tree.leaf(tree, group_info.signer) do
      nil ->
        {:error, :unknown_signer}

      signer ->
        tbs = Message.encode_group_info_tbs(group_info)

        valid? =
          Crypto.verify_with_label(
            signer.signature_key,
            "GroupInfoTBS",
            tbs,
            group_info.signature
          )

        check(valid?, :invalid_group_info_signature)
    end
  end

  defp find_own_leaf(tree, leaf) do
    fetch(
      Enum.find(Tree.leaves(tree), fn {_index, candidate} -> candidate == leaf end),
      :not_in_tree
    )
  end

  # the committer sent the path secret of our lowest common ancestor; the keys
  # above it follow from the committer's filtered direct path
  defp welcome_path_keys(_tree, _leaf_index, _signer, nil), do: {:ok, %{}}

  defp welcome_path_keys(tree, leaf_index, signer, path_secret) do
    ancestor =
      TreeMath.common_ancestor(TreeMath.leaf_to_node(leaf_index), TreeMath.leaf_to_node(signer))

    case Enum.drop_while(Tree.filtered_direct_path(tree, signer), fn {x, _copath} ->
           x != ancestor
         end) do
      [] -> {:error, :invalid_path_secret}
      nodes -> derive_path_keys(tree, Enum.map(nodes, &elem(&1, 0)), path_secret)
    end
  end

  # derives key pairs along `nodes` from the first path secret and checks them
  # against the tree; returns the keys and the commit secret
  defp derive_path_keys(tree, nodes, path_secret) do
    {keys, _commit_secret} = derive_path(nodes, path_secret)

    if Enum.all?(keys, fn {x, {public_key, _private_key}} ->
         Tree.get(tree, x).encryption_key == public_key
       end),
       do: {:ok, Map.new(keys)},
       else: {:error, :path_key_mismatch}
  end

  defp derive_path(nodes, path_secret) do
    Enum.map_reduce(nodes, path_secret, fn x, path_secret ->
      key_pair = HPKE.derive_key_pair(Crypto.derive_secret(path_secret, "node"))
      {{x, key_pair}, Crypto.derive_secret(path_secret, "path")}
    end)
  end

  ## Proposals

  @doc """
  Verifies and queues a proposal sent as an MLSMessage. Returns the queued
  entry, so the caller can apply its own policy before keeping the new group.
  """
  @spec handle_proposal(t(), binary()) :: {:ok, t(), map()} | {:error, atom()}
  def handle_proposal(group, mls_message) do
    with {:ok, message} <- decode_public_message(mls_message),
         {:ok, proposal} <- fetch_content(message, :proposal),
         :ok <- check(message.content.epoch == group.epoch, :wrong_epoch),
         :ok <- verify_message(group, message),
         :ok <- validate_proposal(group, proposal, message.content.sender) do
      ref = Crypto.ref_hash("MLS 1.0 Proposal Reference", Message.authenticated_content(message))
      entry = %{ref: ref, proposal: proposal, sender: message.content.sender}
      {:ok, %{group | proposals: group.proposals ++ [entry]}, entry}
    end
  end

  @doc "Drops queued proposals by reference."
  @spec revoke(t(), [binary()]) :: {:ok, t()} | {:error, :unknown_proposal}
  def revoke(group, refs) do
    known = MapSet.new(group.proposals, & &1.ref)

    if Enum.all?(refs, &MapSet.member?(known, &1)),
      do: {:ok, %{group | proposals: Enum.reject(group.proposals, &(&1.ref in refs))}},
      else: {:error, :unknown_proposal}
  end

  defp validate_proposal(_group, {:add, key_package}, _sender),
    do: KeyPackage.validate(key_package)

  defp validate_proposal(group, {:remove, leaf_index}, _sender),
    do: check(Tree.leaf(group.tree, leaf_index) != nil, :invalid_remove)

  defp validate_proposal(group, {:update, leaf}, {:member, leaf_index}) do
    check(
      leaf.source == :update and LeafNode.verify(leaf, group.group_id, leaf_index),
      :invalid_update
    )
  end

  defp validate_proposal(_group, _proposal, _sender), do: {:error, :invalid_proposal}

  ## Committing

  @doc """
  Commits every queued proposal by reference (RFC 9420, section 12.4.1).
  Returns the Commit as an MLSMessage, a Welcome when members were added, and
  the group as it will be once the Commit is accepted.
  """
  @spec commit(t()) :: {:ok, binary(), binary() | nil, t()} | {:error, atom()}
  def commit(group) do
    proposals = Enum.map(group.proposals, &{&1.proposal, &1.sender})

    with {:ok, tree, added} <- apply_proposals(group, proposals, group.leaf_index) do
      {tree, path, path_secrets, commit_secret, keys} =
        if path_required?(proposals),
          do: create_path(group, tree, added),
          else: {tree, nil, %{}, KeySchedule.zero(), %{}}

      content = %{
        group_id: group.group_id,
        epoch: group.epoch,
        sender: {:member, group.leaf_index},
        authenticated_data: <<>>,
        content:
          {:commit, %{proposals: Enum.map(group.proposals, &{:reference, &1.ref}), path: path}}
      }

      old_context = encode_context(context(group))
      tbs = Message.framed_content_tbs(content, old_context)
      signature = Crypto.sign_with_label(group.signature_private_key, "FramedContentTBS", tbs)

      message = %{
        content: content,
        signature: signature,
        confirmation_tag: nil,
        membership_tag: nil
      }

      {next, confirmation_tag} = advance(group, tree, message, commit_secret)
      message = %{message | confirmation_tag: confirmation_tag}

      membership_tag =
        Crypto.mac(
          group.secrets.membership_key,
          Message.membership_tag_input(message, old_context)
        )

      message = %{message | membership_tag: membership_tag}
      next = %{next | private_keys: prune_keys(Map.merge(group.private_keys, keys), tree)}

      welcome = if added != [], do: welcome(next, confirmation_tag, added, path_secrets)
      {:ok, encode(Message.encode_mls_message({:public_message, message})), welcome, next}
    end
  end

  defp create_path(group, tree, added) do
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
      encode_context(%{context(group) | epoch: group.epoch + 1, tree_hash: Tree.tree_hash(tree)})

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

  defp welcome(group, confirmation_tag, added, path_secrets) do
    group_info = %{
      group_context: context(group),
      extensions: [{Message.extension_ratchet_tree(), encode(Tree.encode(group.tree))}],
      confirmation_tag: confirmation_tag,
      signer: group.leaf_index
    }

    tbs = Message.encode_group_info_tbs(group_info)

    group_info =
      Map.put(
        group_info,
        :signature,
        Crypto.sign_with_label(group.signature_private_key, "GroupInfoTBS", tbs)
      )

    {key, nonce} = KeySchedule.welcome_key_and_nonce(group.secrets.welcome_secret)
    encrypted_group_info = Crypto.seal(key, nonce, "", Message.encode_group_info(group_info))
    me = TreeMath.leaf_to_node(group.leaf_index)

    secrets =
      for {leaf_index, key_package} <- added do
        ancestor = TreeMath.common_ancestor(me, TreeMath.leaf_to_node(leaf_index))

        group_secrets = %{
          joiner_secret: group.secrets.joiner_secret,
          path_secret: Map.get(path_secrets, ancestor)
        }

        {kem_output, ciphertext} =
          Crypto.encrypt_with_label(
            key_package.init_key,
            "Welcome",
            encrypted_group_info,
            encode(Message.encode_group_secrets(group_secrets))
          )

        %{new_member: KeyPackage.ref(key_package), kem_output: kem_output, ciphertext: ciphertext}
      end

    welcome = %{
      cipher_suite: Crypto.cipher_suite(),
      secrets: secrets,
      encrypted_group_info: encrypted_group_info
    }

    encode(Message.encode_welcome(welcome))
  end

  ## Processing commits

  @doc """
  Processes a Commit sent as an MLSMessage (RFC 9420, section 12.4.2). Our own
  commits can't be decrypted, so `cached` must hold the state commit/1 returned.
  """
  @spec handle_commit(t(), binary(), t() | nil) :: {:ok, t()} | {:error, atom()}
  def handle_commit(group, mls_message, cached \\ nil) do
    with {:ok, message} <- decode_public_message(mls_message),
         {:ok, commit} <- fetch_content(message, :commit),
         :ok <- check(message.content.epoch == group.epoch, :wrong_epoch),
         {:member, committer} <- message.content.sender,
         :ok <- verify_message(group, message) do
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

  defp apply_commit(group, message, commit, committer) do
    with {:ok, proposals} <- resolve_proposals(group, commit.proposals, committer),
         :ok <-
           check({:remove, group.leaf_index} not in Enum.map(proposals, &elem(&1, 0)), :removed),
         :ok <- check(commit.path != nil or not path_required?(proposals), :missing_path),
         {:ok, tree, added} <- apply_proposals(group, proposals, committer),
         {:ok, tree, commit_secret, keys} <-
           merge_path(group, tree, commit.path, committer, added) do
      {next, confirmation_tag} = advance(group, tree, message, commit_secret)

      if equal?(confirmation_tag, message.confirmation_tag) do
        {:ok, %{next | private_keys: prune_keys(Map.merge(group.private_keys, keys), tree)}}
      else
        {:error, :invalid_confirmation_tag}
      end
    end
  end

  defp resolve_proposals(group, items, committer) do
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

  defp merge_path(_group, tree, nil, _committer, _added), do: {:ok, tree, KeySchedule.zero(), %{}}

  defp merge_path(group, tree, path, committer, added),
    do: merge_update_path(group, tree, path, committer, added)

  @doc """
  Merges a committer's UpdatePath into `tree` (the tree after the commit's
  proposals) and decrypts it (RFC 9420, section 7.5). Returns the new tree,
  the commit secret and the private keys learned along the way.
  """
  @spec merge_update_path(t(), Tree.t(), map(), non_neg_integer(), list()) ::
          {:ok, Tree.t(), binary(), map()} | {:error, atom()}
  def merge_update_path(group, tree, path, committer, added) do
    leaf = path.leaf_node
    public_keys = Enum.map(path.nodes, & &1.encryption_key)
    filtered = Tree.filtered_direct_path(tree, committer)
    tree_keys = MapSet.new(tree.nodes, fn {_x, node} -> node.encryption_key end)

    with :ok <- check(match?({:commit, _}, leaf.source), :invalid_leaf_source),
         :ok <- check(LeafNode.verify(leaf, group.group_id, committer), :invalid_leaf_signature),
         :ok <-
           check(
             leaf.encryption_key != Tree.leaf(tree, committer).encryption_key,
             :reused_leaf_key
           ),
         :ok <- check(length(public_keys) == length(filtered), :invalid_path_length),
         :ok <-
           check(
             Enum.all?([leaf.encryption_key | public_keys], &(not MapSet.member?(tree_keys, &1))),
             :reused_key
           ) do
      {tree, parent_hash} = Tree.apply_path(tree, committer, public_keys)

      with :ok <- check(leaf.source == {:commit, parent_hash}, :invalid_parent_hash) do
        tree = Tree.set_leaf(tree, committer, leaf)

        provisional =
          encode_context(%{
            context(group)
            | epoch: group.epoch + 1,
              tree_hash: Tree.tree_hash(tree)
          })

        decrypt_path(group, tree, path, filtered, provisional, added)
      end
    end
  end

  # finds the path node whose copath subtree holds us, decrypts its path secret
  # with a key we hold, and derives everything above it
  defp decrypt_path(group, tree, path, filtered, provisional, added) do
    me = TreeMath.leaf_to_node(group.leaf_index)

    new_members =
      Enum.map(added, fn {leaf_index, _key_package} -> TreeMath.leaf_to_node(leaf_index) end)

    with {:ok, position} <-
           fetch(
             Enum.find_index(filtered, fn {_x, copath} -> TreeMath.in_subtree?(me, copath) end),
             :not_in_path
           ),
         {_x, copath} = Enum.at(filtered, position),
         resolution = Tree.resolution(tree, copath) -- new_members,
         ciphertexts = Enum.at(path.nodes, position).ciphertexts,
         :ok <- check(length(ciphertexts) == length(resolution), :invalid_path_length),
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
           |> or_error(:decryption_failed) do
      nodes = filtered |> Enum.drop(position) |> Enum.map(&elem(&1, 0))
      {keys, commit_secret} = derive_path(nodes, path_secret)

      if Enum.all?(keys, fn {x, {public_key, _}} ->
           Tree.get(tree, x).encryption_key == public_key
         end),
         do: {:ok, tree, commit_secret, Map.new(keys)},
         else: {:error, :path_key_mismatch}
    end
  end

  defp find_private_key(group, tree, resolution) do
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

  ## Shared commit steps

  # applies updates, then removes, then adds (RFC 9420, section 12.3)
  defp apply_proposals(group, proposals, committer) do
    updates = for {{:update, leaf}, {:member, index}} <- proposals, do: {index, leaf}
    removes = for {{:remove, index}, _sender} <- proposals, do: index
    adds = for {{:add, key_package}, _sender} <- proposals, do: key_package

    signature_keys =
      MapSet.new(Tree.leaves(group.tree), fn {_index, leaf} -> leaf.signature_key end)

    cond do
      length(Enum.uniq(removes)) != length(removes) or committer in removes ->
        {:error, :invalid_remove}

      Enum.any?(removes, &(Tree.leaf(group.tree, &1) == nil)) ->
        {:error, :invalid_remove}

      Enum.any?(adds, &MapSet.member?(signature_keys, &1.leaf_node.signature_key)) ->
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

  defp path_required?([]), do: true

  defp path_required?(proposals),
    do:
      Enum.any?(proposals, fn {proposal, _sender} -> elem(proposal, 0) in [:update, :remove] end)

  # updates the transcript and key schedule for a commit; returns the next
  # group and the confirmation tag it implies
  defp advance(group, tree, message, commit_secret) do
    confirmed =
      Crypto.hash([group.interim_transcript_hash, Message.confirmed_transcript_input(message)])

    context = %{
      context(group)
      | epoch: group.epoch + 1,
        tree_hash: Tree.tree_hash(tree),
        confirmed_transcript_hash: confirmed
    }

    secrets =
      KeySchedule.advance(group.secrets.init_secret, commit_secret, encode_context(context))

    confirmation_tag = Crypto.mac(secrets.confirmation_key, confirmed)

    next = %{
      group
      | epoch: group.epoch + 1,
        tree: tree,
        secrets: secrets,
        confirmed_transcript_hash: confirmed,
        interim_transcript_hash: interim_transcript_hash(confirmed, confirmation_tag),
        proposals: []
    }

    {next, confirmation_tag}
  end

  ## Message authentication

  defp decode_public_message(mls_message) do
    case Message.decode(mls_message, &Message.decode_mls_message/1) do
      {:ok, {:public_message, message}} -> {:ok, message}
      {:ok, _other} -> {:error, :not_a_public_message}
      error -> error
    end
  end

  defp fetch_content(%{content: %{content: {type, value}}}, type), do: {:ok, value}
  defp fetch_content(_message, _type), do: {:error, :unexpected_content}

  defp verify_message(group, message) do
    context = encode_context(context(group))

    with :ok <- check(message.content.group_id == group.group_id, :wrong_group),
         {:ok, signature_key} <- signer_key(group, message.content.sender),
         tbs = Message.framed_content_tbs(message.content, context),
         :ok <-
           check(
             Crypto.verify_with_label(signature_key, "FramedContentTBS", tbs, message.signature),
             :invalid_signature
           ) do
      verify_membership_tag(group, message, context)
    end
  end

  defp signer_key(group, {:member, leaf_index}) do
    case Tree.leaf(group.tree, leaf_index) do
      nil -> {:error, :unknown_sender}
      leaf -> {:ok, leaf.signature_key}
    end
  end

  defp signer_key(group, {:external, index}) do
    case Enum.at(external_senders(group), index) do
      nil -> {:error, :unknown_sender}
      sender -> {:ok, sender.signature_key}
    end
  end

  defp signer_key(_group, _sender), do: {:error, :unsupported_sender}

  defp verify_membership_tag(group, %{content: %{sender: {:member, _}}} = message, context) do
    expected =
      Crypto.mac(group.secrets.membership_key, Message.membership_tag_input(message, context))

    check(equal?(expected, message.membership_tag), :invalid_membership_tag)
  end

  defp verify_membership_tag(_group, _message, _context), do: :ok

  ## Accessors

  @spec external_senders(t()) :: [map()]
  def external_senders(group) do
    with {_type, data} <- List.keyfind(group.extensions, Message.extension_external_senders(), 0),
         {:ok, senders} <- Message.decode(data, &Message.decode_external_senders/1) do
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

  ## Helpers

  defp encode_context(context), do: encode(Message.encode_group_context(context))

  defp encode(iodata), do: IO.iodata_to_binary(iodata)

  defp interim_transcript_hash(confirmed, confirmation_tag),
    do: Crypto.hash([confirmed, Codec.vector(confirmation_tag)])

  # keeps only the private keys that still match a node in the tree
  defp prune_keys(keys, tree) do
    Map.filter(keys, fn {x, {public_key, _private_key}} ->
      match?(%{encryption_key: ^public_key}, Tree.get(tree, x))
    end)
  end

  defp equal?(a, b) when is_binary(a) and is_binary(b) and byte_size(a) == byte_size(b),
    do: :crypto.hash_equals(a, b)

  defp equal?(_a, _b), do: false

  defp check(true, _reason), do: :ok
  defp check(false, reason), do: {:error, reason}

  defp fetch(nil, reason), do: {:error, reason}
  defp fetch(value, _reason), do: {:ok, value}

  defp or_error(:error, reason), do: {:error, reason}
  defp or_error(ok, _reason), do: ok
end
