defmodule Lingo.Voice.Dave.SessionTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Lingo.MLS.{Codec, Crypto, Framing, KeyPackage, Message, Welcome}
  alias Lingo.Voice.Dave.Session

  @channel 1_234_567_890

  # stands in for the voice gateway: it is the MLS external sender
  defp gateway do
    {signature_key, private_key} = Crypto.generate_signature_key()
    %{signature_key: signature_key, private_key: private_key, credential: {:basic, "gateway"}}
  end

  defp external_sender_package(gateway),
    do:
      IO.iodata_to_binary(
        Welcome.encode_external_sender(Map.take(gateway, [:signature_key, :credential]))
      )

  defp proposal(gateway, epoch, proposal) do
    content = %{
      group_id: <<@channel::64>>,
      epoch: epoch,
      sender: {:external, 0},
      authenticated_data: <<>>,
      content: {:proposal, proposal}
    }

    signature =
      Crypto.sign_with_label(
        gateway.private_key,
        "FramedContentTBS",
        Framing.framed_content_tbs(content, <<>>)
      )

    message = %{
      content: content,
      signature: signature,
      confirmation_tag: nil,
      membership_tag: nil
    }

    Message.encode_mls_message({:public_message, message})
  end

  defp proposals(gateway, epoch, list),
    do:
      IO.iodata_to_binary([
        <<0>>,
        Codec.list(Enum.map(list, &proposal(gateway, epoch, &1)), & &1)
      ])

  defp key_package([{:binary, 26, payload}]),
    do: Codec.decode_exact(payload, &KeyPackage.decode/1)

  # a session that knows everyone, has the external sender, and offered a key package
  defp join(user_id, everyone, gateway) do
    session = Session.new(user_id, @channel) |> Session.clients_connect(everyone -- [user_id])
    {session, []} = Session.handle_binary(session, 25, external_sender_package(gateway), 0)
    {session, out} = Session.set_protocol_version(session, 1, 0)
    {session, key_package(out)}
  end

  # splits the op 28 payload back into the commit and the optional welcome
  defp split_commit_welcome(payload) do
    {_message, welcome} = Message.decode_mls_message(payload)
    commit = binary_part(payload, 0, byte_size(payload) - byte_size(welcome))
    {commit, if(welcome == <<>>, do: nil, else: welcome)}
  end

  defp transcode(from, to, user_id, frame, now \\ 1) do
    {:ok, encrypted, from} = Session.encrypt(from, frame)
    assert encrypted != frame
    {:ok, ^frame, to} = Session.decrypt(to, user_id, encrypted, now)
    {from, to}
  end

  test "three members form a group, talk, and one leaves" do
    gateway = gateway()
    users = [1, 2, 3]
    {alice, _} = join(1, users, gateway)
    {bob, bob_kp} = join(2, users, gateway)
    {carol, carol_kp} = join(3, users, gateway)

    # alice gets the proposals and commits them
    {alice, [{:binary, 28, payload}]} =
      Session.handle_binary(
        alice,
        27,
        proposals(gateway, 0, [{:add, bob_kp}, {:add, carol_kp}]),
        0
      )

    {commit, welcome} = split_commit_welcome(payload)
    assert welcome

    # the gateway announces alice's commit to her and welcomes the others
    {alice, [{:json, 23, %{transition_id: 1}}]} =
      Session.handle_binary(alice, 29, <<1::16, commit::binary>>, 0)

    {bob, [{:json, 23, %{transition_id: 1}}]} =
      Session.handle_binary(bob, 30, <<1::16, welcome::binary>>, 0)

    {carol, [{:json, 23, %{transition_id: 1}}]} =
      Session.handle_binary(carol, 30, <<1::16, welcome::binary>>, 0)

    # nobody sends with the new keys until the transition executes
    assert {:error, :not_ready} = Session.encrypt(alice, "opus")

    [alice, bob, carol] =
      for session <- [alice, bob, carol] do
        {session, []} = Session.handle_json(session, 22, %{"transition_id" => 1}, 0)
        assert Session.active?(session)
        session
      end

    assert Session.epoch_authenticator(alice) == Session.epoch_authenticator(bob)
    assert Session.epoch_authenticator(bob) == Session.epoch_authenticator(carol)

    {alice, bob} = transcode(alice, bob, 1, "alice speaking")
    {alice, carol} = transcode(alice, carol, 1, "alice again")
    {bob, carol} = transcode(bob, carol, 2, "bob speaking")
    {carol, alice} = transcode(carol, alice, 3, "carol speaking")

    # carol leaves: alice and bob both commit, the gateway picks bob's
    remove = proposals(gateway, 1, [{:remove, 2}])
    carol = Session.client_disconnect(carol, 3)

    {alice, [{:binary, 28, _alice_commit}]} =
      Session.handle_binary(Session.client_disconnect(alice, 3), 27, remove, 0)

    {bob, [{:binary, 28, payload}]} =
      Session.handle_binary(Session.client_disconnect(bob, 3), 27, remove, 0)

    {commit, nil} = split_commit_welcome(payload)

    {alice, [{:json, 23, %{transition_id: 2}}]} =
      Session.handle_binary(alice, 29, <<2::16, commit::binary>>, 0)

    {bob, [{:json, 23, %{transition_id: 2}}]} =
      Session.handle_binary(bob, 29, <<2::16, commit::binary>>, 0)

    # frames sent with the old keys still decrypt during the transition
    {:ok, late, _} = Session.encrypt(carol, "carol, late")
    assert {:ok, "carol, late", alice} = Session.decrypt(alice, 3, late, 5_000)

    {alice, []} = Session.handle_json(alice, 22, %{"transition_id" => 2}, 0)
    {bob, []} = Session.handle_json(bob, 22, %{"transition_id" => 2}, 0)

    assert Session.epoch_authenticator(alice) == Session.epoch_authenticator(bob)
    {_alice, _bob} = transcode(alice, bob, 1, "just us now", 6_000)

    # carol's old keys are useless after the expiry
    assert {:error, _reason, _} = Session.decrypt(alice, 3, late, 20_000)
  end

  test "rejects adds for users who are not in the call" do
    gateway = gateway()
    {alice, _} = join(1, [1], gateway)
    {_mallory, mallory_kp} = join(66, [1, 66], gateway)

    assert {^alice, []} =
             Session.handle_binary(alice, 27, proposals(gateway, 0, [{:add, mallory_kp}]), 0)
  end

  test "a broken welcome is flagged and a new key package is offered" do
    gateway = gateway()
    {bob, _} = join(2, [1, 2], gateway)

    assert {bob, [{:json, 31, %{transition_id: 7}}, {:binary, 26, _key_package}]} =
             Session.handle_binary(bob, 30, <<7::16, "garbage">>, 0)

    refute Session.active?(bob)
  end

  test "a sole member resets into a fresh group immediately" do
    gateway = gateway()
    {alice, _} = join(1, [1], gateway)

    # prepare_epoch(1) starts over; an empty proposal list produces a commit for transition 0
    {alice, [{:binary, 26, _}]} =
      Session.handle_json(alice, 24, %{"epoch" => 1, "protocol_version" => 1}, 0)

    {alice, [{:binary, 28, payload}]} =
      Session.handle_binary(alice, 27, proposals(gateway, 0, []), 0)

    {commit, nil} = split_commit_welcome(payload)

    {alice, []} = Session.handle_binary(alice, 29, <<0::16, commit::binary>>, 0)
    assert Session.active?(alice)
  end

  test "downgrading to passthrough and back" do
    gateway = gateway()
    {alice, _} = join(1, [1, 2], gateway)
    {bob, bob_kp} = join(2, [1, 2], gateway)

    {alice, [{:binary, 28, payload}]} =
      Session.handle_binary(alice, 27, proposals(gateway, 0, [{:add, bob_kp}]), 0)

    {commit, welcome} = split_commit_welcome(payload)
    {alice, []} = Session.handle_binary(alice, 29, <<0::16, commit::binary>>, 0)
    {bob, []} = Session.handle_binary(bob, 30, <<0::16, welcome::binary>>, 0)
    {alice, bob} = transcode(alice, bob, 1, "encrypted")

    # a client without DAVE joins: everyone downgrades
    {alice, [{:json, 23, _}]} =
      Session.handle_json(alice, 21, %{"transition_id" => 3, "protocol_version" => 0}, 0)

    {bob, [{:json, 23, _}]} =
      Session.handle_json(bob, 21, %{"transition_id" => 3, "protocol_version" => 0}, 0)

    {alice, []} = Session.handle_json(alice, 22, %{"transition_id" => 3}, 0)
    {_bob, []} = Session.handle_json(bob, 22, %{"transition_id" => 3}, 0)

    assert {:ok, "plain", alice} = Session.encrypt(alice, "plain")
    assert {:ok, "from someone", _alice} = Session.decrypt(alice, 9, "from someone", 1)
  end
end
