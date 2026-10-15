defmodule Lingo.MLS.GroupTest do
  use ExUnit.Case, async: true

  alias Lingo.MLS.{Crypto, Framing, Group, HPKE, KeyPackage, LeafNode, Message, Welcome}

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
         Welcome.encode_external_senders([Map.take(sender, [:signature_key, :credential])])
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

  defp refresh_member(member) do
    {encryption_key, encryption_private_key} = HPKE.generate_key_pair()
    {init_key, init_private_key} = HPKE.generate_key_pair()

    leaf =
      %{member.key_package.leaf_node | encryption_key: encryption_key}
      |> LeafNode.sign(member.signature_private_key)

    key_package =
      KeyPackage.sign(
        %KeyPackage{init_key: init_key, leaf_node: leaf},
        member.signature_private_key
      )

    %{
      member
      | key_package: key_package,
        encryption_private_key: encryption_private_key,
        init_private_key: init_private_key
    }
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

    tbs = Framing.framed_content_tbs(content, <<>>)
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

    test "two distinct Add proposals for the same signature key", %{
      group: group,
      sender: sender,
      bob: bob
    } do
      replacement = refresh_member(bob)

      {:ok, group, _} =
        Group.handle_proposal(group, propose(group, sender, {:add, bob.key_package}))

      {:ok, group, _} =
        Group.handle_proposal(group, propose(group, sender, {:add, replacement.key_package}))

      assert {:error, :duplicate_member} = Group.commit(group)
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

  test "a commit can replace a removed client's key package while keeping its signature identity" do
    sender = external_sender()
    [alice, bob, carol] = Enum.map([1, 2, 3], &member/1)
    group = create(alice, sender)

    {:ok, group, _} =
      Group.handle_proposal(group, propose(group, sender, {:add, bob.key_package}))

    {:ok, group, _} =
      Group.handle_proposal(group, propose(group, sender, {:add, carol.key_package}))

    {:ok, _, initial_welcome, group} = Group.commit(group)
    {:ok, carol_group} = join_member(initial_welcome, carol)
    replacement = refresh_member(bob)
    remove = propose(group, sender, {:remove, 1})
    add = propose(group, sender, {:add, replacement.key_package})

    [group, carol_group] =
      for receiver <- [group, carol_group] do
        {:ok, receiver, _} = Group.handle_proposal(receiver, remove)
        {:ok, receiver, _} = Group.handle_proposal(receiver, add)
        receiver
      end

    assert {:ok, commit, welcome, next} = Group.commit(group)
    assert {:ok, carol_next} = Group.handle_commit(carol_group, commit)
    assert {:ok, joined} = join_member(welcome, replacement)
    assert Group.epoch_authenticator(joined) == Group.epoch_authenticator(next)
    assert Group.epoch_authenticator(carol_next) == Group.epoch_authenticator(next)
    assert identities(next) == [<<1::64>>, <<2::64>>, <<3::64>>]
  end
end
