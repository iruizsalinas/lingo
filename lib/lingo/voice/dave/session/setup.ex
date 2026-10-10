defmodule Lingo.Voice.Dave.Session.Setup do
  @moduledoc false

  # Starting over: a fresh leaf, a pending group and a new key package, or passthrough when DAVE is off.

  alias Lingo.MLS.{Group, HPKE, KeyPackage, LeafNode, Message, Welcome}
  alias Lingo.Voice.Dave.Session.{Transition, Util}

  # starts over waiting to be added: a fresh leaf, a fresh pending group and a
  # new key package, or plain passthrough when DAVE is off
  def reinit(%{protocol_version: 0} = session, now) do
    session = reset(session)
    {%{Transition.passthrough(session, true, now) | encryptor: nil, pending_encryptor: nil}, []}
  end

  def reinit(session, _now) do
    {encryption_key, encryption_private_key} = HPKE.generate_key_pair()
    {signature_key, signature_private_key} = session.signature_key

    leaf =
      %LeafNode{
        encryption_key: encryption_key,
        signature_key: signature_key,
        credential: {:basic, <<session.user_id::64>>},
        capabilities: LeafNode.default_capabilities(),
        source: LeafNode.unlimited_lifetime()
      }
      |> LeafNode.sign(signature_private_key)

    {init_key, init_private_key} = HPKE.generate_key_pair()

    key_package =
      KeyPackage.sign(%KeyPackage{init_key: init_key, leaf_node: leaf}, signature_private_key)

    session =
      %{
        reset(session)
        | leaf: {leaf, encryption_private_key},
          key_package: {key_package, init_private_key}
      }
      |> create_pending_group()

    {session, [{:binary, 26, IO.iodata_to_binary(KeyPackage.encode(key_package))}]}
  end

  def reset(session) do
    %{
      session
      | leaf: nil,
        key_package: nil,
        pending_group: nil,
        pending_commit: nil,
        group: nil,
        staged: nil,
        outbound: nil
    }
  end

  def create_pending_group(
        %{external_sender: sender, leaf: {leaf, encryption_private_key}} = session
      )
      when sender != nil do
    {_signature_key, signature_private_key} = session.signature_key

    extensions = [
      {Message.extension_external_senders(),
       Util.encode(Welcome.encode_external_senders([sender]))}
    ]

    group =
      Group.create(
        group_id(session),
        leaf,
        encryption_private_key,
        signature_private_key,
        extensions
      )

    %{session | pending_group: group}
  end

  def create_pending_group(session), do: session

  # our MLS group is identified by the channel id, as a big-endian uint64
  def group_id(session), do: <<session.channel_id::64>>

  def recognized_users(session), do: MapSet.put(session.connected, session.user_id)
end
