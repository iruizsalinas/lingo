defmodule Lingo.MLS.GroupTest do
  use ExUnit.Case, async: true

  import Lingo.Test.MLSVectors

  alias Lingo.MLS.{Codec, Crypto, Group, HPKE, KeyPackage, KeySchedule, LeafNode, Message, Tree}

  describe "IETF vectors" do
    test "key schedule" do
      [vector] = load("key-schedule")
      group_id = hex(vector["group_id"])

      Enum.reduce(
        Enum.with_index(vector["epochs"]),
        hex(vector["initial_init_secret"]),
        fn {epoch, n}, init_secret ->
          context =
            Message.encode_group_context(%{
              cipher_suite: 2,
              group_id: group_id,
              epoch: n,
              tree_hash: hex(epoch["tree_hash"]),
              confirmed_transcript_hash: hex(epoch["confirmed_transcript_hash"]),
              extensions: []
            })
            |> IO.iodata_to_binary()

          assert context == hex(epoch["group_context"])

          secrets =
            KeySchedule.advance(
              init_secret,
              hex(epoch["commit_secret"]),
              context,
              hex(epoch["psk_secret"])
            )

          for key <-
                ~w(joiner_secret welcome_secret init_secret sender_data_secret encryption_secret
                      exporter_secret epoch_authenticator external_secret confirmation_key
                      membership_key resumption_psk) do
            assert Map.fetch!(secrets, String.to_atom(key)) == hex(epoch[key]),
                   "#{key} in epoch #{n}"
          end

          assert elem(HPKE.derive_key_pair(secrets.external_secret), 0) ==
                   hex(epoch["external_pub"])

          %{
            "label" => label,
            "context" => exporter_context,
            "length" => length,
            "secret" => secret
          } = epoch["exporter"]

          # the vectors use the hex string itself as the label
          assert KeySchedule.export(secrets.exporter_secret, label, hex(exporter_context), length) ==
                   hex(secret)

          secrets.init_secret
        end
      )
    end

    test "transcript hashes" do
      [vector] = load("transcript-hashes")

      <<1::16, rest::binary>> = hex(vector["authenticated_content"])
      {content, rest} = Message.decode_framed_content(rest)
      {signature, rest} = Codec.decode_vector(rest)
      {confirmation_tag, <<>>} = Codec.decode_vector(rest)

      message = %{content: content, signature: signature}

      confirmed =
        Crypto.hash([
          hex(vector["interim_transcript_hash_before"]),
          Message.confirmed_transcript_input(message)
        ])

      assert confirmed == hex(vector["confirmed_transcript_hash_after"])
      assert Crypto.mac(hex(vector["confirmation_key"]), confirmed) == confirmation_tag

      assert Crypto.hash([confirmed, Codec.vector(confirmation_tag)]) ==
               hex(vector["interim_transcript_hash_after"])
    end

    test "passive client joining from a Welcome" do
      cases = Enum.filter(load("passive-client-welcome"), &(&1["external_psks"] == []))
      assert length(cases) == 4

      for vector <- cases do
        assert {:ok, group} = join(vector)
        assert Group.epoch_authenticator(group) == hex(vector["initial_epoch_authenticator"])
      end
    end

    # the passive-client commit vectors all join through a Welcome carrying a
    # pre-shared key, which DAVE never uses; these cover the same ground
    test "treekem: merging and decrypting UpdatePaths from other implementations" do
      for vector <- load("treekem") do
        tree = Codec.decode_exact(hex(vector["ratchet_tree"]), &Tree.decode/1)

        for update <- vector["update_paths"],
            leaf <- vector["leaves_private"],
            leaf["index"] != update["sender"] do
          group = private_group(vector, tree, leaf)
          path = Codec.decode_exact(hex(update["update_path"]), &Message.decode_update_path/1)

          assert {:ok, new_tree, commit_secret, keys} =
                   Group.merge_update_path(group, tree, path, update["sender"], [])

          assert Tree.tree_hash(new_tree) == hex(update["tree_hash_after"])
          assert commit_secret == hex(update["commit_secret"])
          assert map_size(keys) > 0
        end
      end
    end
  end

  # a member's view of a vector tree: its leaf key plus the path secrets it holds
  defp private_group(vector, tree, leaf) do
    leaf_x = 2 * leaf["index"]

    path_keys =
      Map.new(leaf["path_secrets"], fn %{"node" => x, "path_secret" => path_secret} ->
        {x, HPKE.derive_key_pair(Crypto.derive_secret(hex(path_secret), "node"))}
      end)

    %Group{
      group_id: hex(vector["group_id"]),
      epoch: vector["epoch"] - 1,
      tree: tree,
      leaf_index: leaf["index"],
      signature_private_key: hex(leaf["signature_priv"]),
      secrets: %{},
      confirmed_transcript_hash: hex(vector["confirmed_transcript_hash"]),
      private_keys:
        Map.put(
          path_keys,
          leaf_x,
          {Tree.get(tree, leaf_x).encryption_key, hex(leaf["encryption_priv"])}
        )
    }
  end

  defp join(vector) do
    {:ok, {:key_package, key_package}} =
      Message.decode(hex(vector["key_package"]), &Message.decode_mls_message/1)

    {:ok, {:welcome, _}} = Message.decode(hex(vector["welcome"]), &Message.decode_mls_message/1)
    <<1::16, 3::16, welcome::binary>> = hex(vector["welcome"])

    Group.join(
      welcome,
      key_package,
      hex(vector["init_priv"]),
      hex(vector["encryption_priv"]),
      hex(vector["signature_priv"]),
      hex(vector["ratchet_tree"])
    )
  end

  ## Our own groups, end to end

  defmodule Member do
    @moduledoc false
    defstruct [
      :id,
      :signature_key,
      :signature_private_key,
      :encryption_private_key,
      :init_private_key,
      :key_package
    ]
  end

  # an external sender standing in for the DAVE voice gateway
  defp external_sender do
    {public_key, private_key} = Crypto.generate_signature_key()
    %{signature_key: public_key, private_key: private_key, credential: {:basic, "gateway"}}
  end

  defp member(id) do
    {signature_key, signature_private_key} = Crypto.generate_signature_key()
    {encryption_key, encryption_private_key} = HPKE.generate_key_pair()
    {init_key, init_private_key} = HPKE.generate_key_pair()

    leaf =
      %LeafNode{
        encryption_key: encryption_key,
        signature_key: signature_key,
        credential: {:basic, <<id::64>>},
        capabilities: LeafNode.default_capabilities(),
        source: LeafNode.unlimited_lifetime()
      }
      |> LeafNode.sign(signature_private_key)

    key_package =
      KeyPackage.sign(%KeyPackage{init_key: init_key, leaf_node: leaf}, signature_private_key)

    %Member{
      id: id,
      signature_key: signature_key,
      signature_private_key: signature_private_key,
      encryption_private_key: encryption_private_key,
      init_private_key: init_private_key,
      key_package: key_package
    }
  end

  defp create(member, sender) do
    extensions = [
      {Message.extension_external_senders(),
       IO.iodata_to_binary(
         Message.encode_external_senders([Map.take(sender, [:signature_key, :credential])])
       )}
    ]

    Group.create(
      "channel",
      member.key_package.leaf_node,
      member.encryption_private_key,
      member.signature_private_key,
      extensions
    )
  end

  # an external-sender proposal, as the voice gateway would send it
  defp propose(group, sender, proposal) do
    content = %{
      group_id: group.group_id,
      epoch: group.epoch,
      sender: {:external, 0},
      authenticated_data: <<>>,
      content: {:proposal, proposal}
    }

    tbs = Message.framed_content_tbs(content, <<>>)
    signature = Crypto.sign_with_label(sender.private_key, "FramedContentTBS", tbs)

    message = %{
      content: content,
      signature: signature,
      confirmation_tag: nil,
      membership_tag: nil
    }

    IO.iodata_to_binary(Message.encode_mls_message({:public_message, message}))
  end

  defp join_member(welcome, member) do
    Group.join(
      welcome,
      member.key_package,
      member.init_private_key,
      member.encryption_private_key,
      member.signature_private_key
    )
  end

  defp identities(group),
    do: for({_index, leaf} <- Group.roster(group), do: elem(leaf.credential, 1))

  test "three members join, agree on keys, and one leaves" do
    sender = external_sender()
    [alice, bob, carol] = Enum.map([1, 2, 3], &member/1)

    # alice creates the group, the gateway proposes bob and carol, alice commits
    alice_group = create(alice, sender)
    add_bob = propose(alice_group, sender, {:add, bob.key_package})
    add_carol = propose(alice_group, sender, {:add, carol.key_package})

    {:ok, alice_group, _} = Group.handle_proposal(alice_group, add_bob)
    {:ok, alice_group, _} = Group.handle_proposal(alice_group, add_carol)
    {:ok, commit, welcome, alice_next} = Group.commit(alice_group)
    assert welcome

    # alice can't decrypt her own commit, she keeps the state commit/1 returned
    {:ok, alice_group} = Group.handle_commit(alice_group, commit, alice_next)
    {:ok, bob_group} = join_member(welcome, bob)
    {:ok, carol_group} = join_member(welcome, carol)

    groups = [alice_group, bob_group, carol_group]
    assert Enum.uniq(Enum.map(groups, &Group.epoch_authenticator/1)) |> length() == 1

    assert Enum.uniq(
             Enum.map(groups, &Group.export(&1, "Discord Secure Frames v0", <<1::64-little>>, 16))
           )
           |> length() == 1

    assert identities(bob_group) == [<<1::64>>, <<2::64>>, <<3::64>>]

    # the gateway removes carol; bob commits, which needs an UpdatePath
    remove_carol = propose(bob_group, sender, {:remove, 2})
    {:ok, alice_group, _} = Group.handle_proposal(alice_group, remove_carol)
    {:ok, bob_group, _} = Group.handle_proposal(bob_group, remove_carol)
    {:ok, carol_group, _} = Group.handle_proposal(carol_group, remove_carol)

    {:ok, commit, nil, bob_next} = Group.commit(bob_group)
    {:ok, bob_group} = Group.handle_commit(bob_group, commit, bob_next)
    {:ok, alice_group} = Group.handle_commit(alice_group, commit)
    assert {:error, :removed} = Group.handle_commit(carol_group, commit)

    assert Group.epoch_authenticator(alice_group) == Group.epoch_authenticator(bob_group)
    assert identities(alice_group) == [<<1::64>>, <<2::64>>]
    assert alice_group.epoch == 2
  end

  test "a member added after an UpdatePath derives the new path keys" do
    sender = external_sender()
    [alice, bob, carol, dave] = Enum.map(1..4, &member/1)

    group = create(alice, sender)

    {:ok, group, _} =
      Group.handle_proposal(group, propose(group, sender, {:add, bob.key_package}))

    {:ok, group, _} =
      Group.handle_proposal(group, propose(group, sender, {:add, carol.key_package}))

    {:ok, commit, welcome, next} = Group.commit(group)
    {:ok, alice_group} = Group.handle_commit(group, commit, next)
    {:ok, bob_group} = join_member(welcome, bob)
    {:ok, carol_group} = join_member(welcome, carol)

    # carol removes bob (with a path) and adds dave in the same commit
    remove_bob = propose(carol_group, sender, {:remove, 1})
    add_dave = propose(carol_group, sender, {:add, dave.key_package})

    [alice_group, bob_group, carol_group] =
      for group <- [alice_group, bob_group, carol_group] do
        {:ok, group, _} = Group.handle_proposal(group, remove_bob)
        {:ok, group, _} = Group.handle_proposal(group, add_dave)
        group
      end

    {:ok, commit, welcome, carol_next} = Group.commit(carol_group)
    {:ok, carol_group} = Group.handle_commit(carol_group, commit, carol_next)
    {:ok, alice_group} = Group.handle_commit(alice_group, commit)
    {:error, :removed} = Group.handle_commit(bob_group, commit)
    {:ok, dave_group} = join_member(welcome, dave)

    authenticators =
      Enum.map([alice_group, carol_group, dave_group], &Group.epoch_authenticator/1)

    assert length(Enum.uniq(authenticators)) == 1
    assert identities(dave_group) == [<<1::64>>, <<4::64>>, <<3::64>>]

    # and the new member can follow the next commit, which needs its path keys
    remove_alice = propose(carol_group, sender, {:remove, 0})
    {:ok, carol_group, _} = Group.handle_proposal(carol_group, remove_alice)
    {:ok, dave_group, _} = Group.handle_proposal(dave_group, remove_alice)
    {:ok, commit, nil, carol_next} = Group.commit(carol_group)
    {:ok, carol_group} = Group.handle_commit(carol_group, commit, carol_next)
    {:ok, dave_group} = Group.handle_commit(dave_group, commit)
    assert Group.epoch_authenticator(carol_group) == Group.epoch_authenticator(dave_group)
  end

  describe "rejects" do
    setup do
      sender = external_sender()
      [alice, bob] = Enum.map([1, 2], &member/1)
      %{sender: sender, bob: bob, group: create(alice, sender)}
    end

    test "proposals from an unknown external sender", %{group: group, bob: bob} do
      assert {:error, :invalid_signature} =
               Group.handle_proposal(
                 group,
                 propose(group, external_sender(), {:add, bob.key_package})
               )
    end

    test "proposals for another epoch", %{group: group, sender: sender, bob: bob} do
      message = propose(%{group | epoch: 5}, sender, {:add, bob.key_package})
      assert {:error, :wrong_epoch} = Group.handle_proposal(group, message)
    end

    test "invalid key packages", %{group: group, sender: sender, bob: bob} do
      key_package = %{bob.key_package | init_key: bob.key_package.leaf_node.encryption_key}

      assert {:error, :reused_init_key} =
               Group.handle_proposal(group, propose(group, sender, {:add, key_package}))
    end

    test "commits for unknown proposals and tampered commits", %{
      group: group,
      sender: sender,
      bob: bob
    } do
      {:ok, with_proposal, _} =
        Group.handle_proposal(group, propose(group, sender, {:add, bob.key_package}))

      {:ok, commit, _welcome, _next} = Group.commit(with_proposal)

      # a second member seeing the commit without the proposal
      other = %{with_proposal | leaf_index: 1, proposals: []}
      assert {:error, _} = Group.handle_commit(other, commit)

      tampered = binary_part(commit, 0, byte_size(commit) - 1) <> <<0>>
      assert {:error, _} = Group.handle_commit(with_proposal, tampered)
    end

    test "garbage", %{group: group} do
      assert {:error, :malformed} = Group.handle_proposal(group, <<1, 2, 3>>)
      assert {:error, :malformed} = Group.handle_commit(group, <<0, 1, 0, 1>>)
    end
  end
end
