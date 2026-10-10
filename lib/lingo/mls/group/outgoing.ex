defmodule Lingo.MLS.Group.Outgoing do
  @moduledoc false

  # Committing queued proposals, and the Welcome for members it adds (RFC 9420, section 12.4).

  alias Lingo.MLS.{Crypto, Framing, KeyPackage, KeySchedule, Message, Tree, TreeMath, Welcome}

  alias Lingo.MLS.Group
  alias Lingo.MLS.Group.{Epoch, Path, Util}

  @spec commit(Group.t()) :: {:ok, binary(), binary() | nil, Group.t()} | {:error, atom()}
  def commit(group) do
    proposals = Enum.map(group.proposals, &{&1.proposal, &1.sender})

    with {:ok, tree, added} <- Epoch.apply_proposals(group, proposals, group.leaf_index) do
      {tree, path, path_secrets, commit_secret, keys} =
        if Epoch.path_required?(proposals),
          do: Path.create_path(group, tree, added),
          else: {tree, nil, %{}, KeySchedule.zero(), %{}}

      content = %{
        group_id: group.group_id,
        epoch: group.epoch,
        sender: {:member, group.leaf_index},
        authenticated_data: <<>>,
        content:
          {:commit, %{proposals: Enum.map(group.proposals, &{:reference, &1.ref}), path: path}}
      }

      old_context = Util.encode_context(Group.context(group))
      tbs = Framing.framed_content_tbs(content, old_context)
      signature = Crypto.sign_with_label(group.signature_private_key, "FramedContentTBS", tbs)

      message = %{
        content: content,
        signature: signature,
        confirmation_tag: nil,
        membership_tag: nil
      }

      {next, confirmation_tag} = Epoch.advance(group, tree, message, commit_secret)
      message = %{message | confirmation_tag: confirmation_tag}

      membership_tag =
        Crypto.mac(
          group.secrets.membership_key,
          Framing.membership_tag_input(message, old_context)
        )

      message = %{message | membership_tag: membership_tag}
      next = %{next | private_keys: Util.prune_keys(Map.merge(group.private_keys, keys), tree)}

      welcome = if added != [], do: welcome(next, confirmation_tag, added, path_secrets)
      {:ok, Util.encode(Message.encode_mls_message({:public_message, message})), welcome, next}
    end
  end

  def welcome(group, confirmation_tag, added, path_secrets) do
    group_info = %{
      group_context: Group.context(group),
      extensions: [{Message.extension_ratchet_tree(), Util.encode(Tree.encode(group.tree))}],
      confirmation_tag: confirmation_tag,
      signer: group.leaf_index
    }

    tbs = Welcome.encode_group_info_tbs(group_info)

    group_info =
      Map.put(
        group_info,
        :signature,
        Crypto.sign_with_label(group.signature_private_key, "GroupInfoTBS", tbs)
      )

    {key, nonce} = KeySchedule.welcome_key_and_nonce(group.secrets.welcome_secret)
    encrypted_group_info = Crypto.seal(key, nonce, "", Welcome.encode_group_info(group_info))
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
            Util.encode(Welcome.encode_group_secrets(group_secrets))
          )

        %{new_member: KeyPackage.ref(key_package), kem_output: kem_output, ciphertext: ciphertext}
      end

    welcome = %{
      cipher_suite: Crypto.cipher_suite(),
      secrets: secrets,
      encrypted_group_info: encrypted_group_info
    }

    Util.encode(Welcome.encode_welcome(welcome))
  end
end
