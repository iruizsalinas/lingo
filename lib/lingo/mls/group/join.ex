defmodule Lingo.MLS.Group.Join do
  @moduledoc false

  # Joining a group from a Welcome (RFC 9420, section 12.4.3).

  alias Lingo.MLS.{Crypto, HPKE, KeyPackage, KeySchedule, Message, Tree, TreeMath, Welcome}

  alias Lingo.MLS.Group
  alias Lingo.MLS.Group.{Path, Util}

  @spec join(
          binary(),
          KeyPackage.Lingo.MLS.t(),
          binary(),
          binary(),
          binary(),
          binary() | nil
        ) ::
          {:ok, Lingo.MLS.t()} | {:error, atom()}
  def join(
        welcome,
        key_package,
        init_private_key,
        encryption_private_key,
        signature_private_key,
        ratchet_tree \\ nil
      ) do
    ref = KeyPackage.ref(key_package)

    with {:ok, welcome} <- Message.decode(welcome, &Welcome.decode_welcome/1),
         :ok <-
           Util.check(welcome.cipher_suite == Crypto.cipher_suite(), :unsupported_cipher_suite),
         {:ok, entry} <-
           Util.fetch(Enum.find(welcome.secrets, &(&1.new_member == ref)), :not_for_us),
         {:ok, group_secrets} <- decrypt_group_secrets(welcome, entry, init_private_key),
         {:ok, group_info} <- decrypt_group_info(welcome, group_secrets.joiner_secret),
         context = group_info.group_context,
         :ok <-
           Util.check(context.cipher_suite == Crypto.cipher_suite(), :unsupported_cipher_suite),
         {:ok, tree} <- welcome_tree(group_info, ratchet_tree),
         :ok <- Util.check(Tree.tree_hash(tree) == context.tree_hash, :tree_hash_mismatch),
         :ok <- Tree.validate(tree, context.group_id),
         :ok <- verify_group_info(tree, group_info),
         {:ok, {leaf_index, leaf}} <- find_own_leaf(tree, key_package.leaf_node),
         :ok <-
           Util.check(
             HPKE.public_key(encryption_private_key) == leaf.encryption_key,
             :key_mismatch
           ),
         {:ok, path_keys} <-
           Path.welcome_path_keys(tree, leaf_index, group_info.signer, group_secrets.path_secret) do
      secrets = KeySchedule.join(group_secrets.joiner_secret, Util.encode_context(context))

      if Util.equal?(
           Crypto.mac(secrets.confirmation_key, context.confirmed_transcript_hash),
           group_info.confirmation_tag
         ) do
        group = %Group{
          group_id: context.group_id,
          epoch: context.epoch,
          tree: tree,
          leaf_index: leaf_index,
          signature_private_key: signature_private_key,
          secrets: secrets,
          extensions: context.extensions,
          confirmed_transcript_hash: context.confirmed_transcript_hash,
          interim_transcript_hash:
            Util.interim_transcript_hash(
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

  def decrypt_group_secrets(welcome, entry, init_private_key) do
    case Crypto.decrypt_with_label(
           init_private_key,
           "Welcome",
           welcome.encrypted_group_info,
           entry.kem_output,
           entry.ciphertext
         ) do
      {:ok, plaintext} -> Message.decode(plaintext, &Welcome.decode_group_secrets/1)
      :error -> {:error, :decryption_failed}
    end
  end

  def decrypt_group_info(welcome, joiner_secret) do
    {key, nonce} = KeySchedule.welcome_key_and_nonce(KeySchedule.welcome_secret(joiner_secret))

    case Crypto.open(key, nonce, "", welcome.encrypted_group_info) do
      {:ok, plaintext} -> Message.decode(plaintext, &Welcome.decode_group_info/1)
      :error -> {:error, :decryption_failed}
    end
  end

  def welcome_tree(group_info, nil) do
    case List.keyfind(group_info.extensions, Message.extension_ratchet_tree(), 0) do
      {_type, data} -> Message.decode(data, &Tree.decode/1)
      nil -> {:error, :missing_ratchet_tree}
    end
  end

  def welcome_tree(_group_info, ratchet_tree), do: Message.decode(ratchet_tree, &Tree.decode/1)

  def verify_group_info(tree, group_info) do
    case Tree.leaf(tree, group_info.signer) do
      nil ->
        {:error, :unknown_signer}

      signer ->
        tbs = Welcome.encode_group_info_tbs(group_info)

        valid? =
          Crypto.verify_with_label(
            signer.signature_key,
            "GroupInfoTBS",
            tbs,
            group_info.signature
          )

        Util.check(valid?, :invalid_group_info_signature)
    end
  end

  def find_own_leaf(tree, leaf) do
    Util.fetch(
      Enum.find(Tree.leaves(tree), fn {_index, candidate} -> candidate == leaf end),
      :not_in_tree
    )
  end
end
