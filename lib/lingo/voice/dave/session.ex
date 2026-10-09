defmodule Lingo.Voice.Dave.Session do
  @moduledoc false

  # The DAVE protocol state machine for one voice connection, following
  # libdave's mls::Session and the session handling in @discordjs/voice.
  #
  # It is pure: each handler takes the session and a gateway message and
  # returns the new session plus the messages to send back, as
  # `{:json, opcode, data}` or `{:binary, opcode, payload}`. Times are
  # monotonic milliseconds.
  #
  # Group lifecycle, in short: we offer a key package (op 26) whenever we are
  # waiting to be added. The gateway, our MLS external sender, proposes adds
  # and removes (op 27); we commit them (op 28) and it announces the winning
  # commit (op 29), or welcomes us into the group (op 30). New keys are used
  # for receiving right away, and for sending once the transition executes.

  alias Lingo.MLS.{Codec, Crypto, Group, HPKE, KeyPackage, LeafNode, Message}
  alias Lingo.Voice.Dave.{Decryptor, Encryptor, Frame, KeyRatchet}

  require Logger

  # how long receivers keep accepting unencrypted media around a downgrade
  @transition_expiry 10_000
  @downgrade_expiry 24_000

  @enforce_keys [:user_id, :channel_id, :signature_key]
  defstruct [
    :user_id,
    :channel_id,
    :signature_key,
    :external_sender,
    :leaf,
    :key_package,
    :pending_group,
    :pending_commit,
    :group,
    :staged,
    :outbound,
    :encryptor,
    :pending_encryptor,
    protocol_version: 0,
    connected: MapSet.new(),
    transitions: %{},
    decryptors: %{},
    passthrough: true
  ]

  @type message :: {:json, non_neg_integer(), map()} | {:binary, non_neg_integer(), binary()}
  @type t :: %__MODULE__{}

  @spec max_protocol_version() :: non_neg_integer()
  def max_protocol_version, do: 1

  @spec new(non_neg_integer(), non_neg_integer()) :: t()
  def new(user_id, channel_id) do
    # one signature key for the whole connection, as libdave's transient key
    %__MODULE__{
      user_id: user_id,
      channel_id: channel_id,
      signature_key: Crypto.generate_signature_key()
    }
  end

  @doc "Whether media is end-to-end encrypted right now."
  @spec active?(t()) :: boolean()
  def active?(session), do: session.protocol_version > 0 and session.encryptor != nil

  @doc "Whether `encrypt/2` can take media now: DAVE is off, or our keys are in place."
  @spec ready?(t()) :: boolean()
  def ready?(session), do: session.protocol_version == 0 or session.encryptor != nil

  @spec epoch_authenticator(t()) :: binary() | nil
  def epoch_authenticator(%{group: nil}), do: nil
  def epoch_authenticator(%{group: group}), do: Group.epoch_authenticator(group)

  ## Gateway events

  @doc "The protocol version from the session description (op 4)."
  @spec set_protocol_version(t(), non_neg_integer(), integer()) :: {t(), [message()]}
  def set_protocol_version(session, version, now),
    do: reinit(%{session | protocol_version: version}, now)

  @spec clients_connect(t(), [non_neg_integer()]) :: t()
  def clients_connect(session, user_ids),
    do: %{session | connected: MapSet.union(session.connected, MapSet.new(user_ids))}

  @spec client_disconnect(t(), non_neg_integer()) :: t()
  def client_disconnect(session, user_id),
    do: %{session | connected: MapSet.delete(session.connected, user_id)}

  @doc "Handles a JSON DAVE opcode (21, 22 and 24)."
  @spec handle_json(t(), non_neg_integer(), map(), integer()) :: {t(), [message()]}
  def handle_json(
        session,
        21,
        %{"transition_id" => transition_id, "protocol_version" => version},
        now
      ) do
    session = put_in(session.transitions[transition_id], version)

    cond do
      transition_id == 0 ->
        execute_transition(session, 0, now)

      version == 0 ->
        {passthrough(session, true, now, @downgrade_expiry), [ready(transition_id)]}

      true ->
        {session, [ready(transition_id)]}
    end
  end

  def handle_json(session, 22, %{"transition_id" => transition_id}, now),
    do: execute_transition(session, transition_id, now)

  def handle_json(session, 24, %{"epoch" => 1, "protocol_version" => version}, now),
    do: reinit(%{session | protocol_version: version}, now)

  def handle_json(session, _op, _data, _now), do: {session, []}

  @doc "Handles a binary DAVE opcode (25, 27, 29 and 30); `payload` follows the opcode byte."
  @spec handle_binary(t(), non_neg_integer(), binary(), integer()) :: {t(), [message()]}
  def handle_binary(session, 25, payload, _now) do
    case Message.decode(payload, &Message.decode_external_sender/1) do
      {:ok, sender} when session.group == nil ->
        {create_pending_group(%{session | external_sender: sender}), []}

      _invalid_or_too_late ->
        Logger.warning("Lingo DAVE ignored an external sender package")
        {session, []}
    end
  end

  def handle_binary(session, 27, <<revoke, payload::binary>>, _now) when revoke in [0, 1] do
    case process_proposals(session, revoke == 1, payload) do
      {:ok, session, messages} ->
        {session, messages}

      {:error, reason} ->
        Logger.warning("Lingo DAVE could not process proposals: #{inspect(reason)}")
        {session, []}
    end
  end

  def handle_binary(session, 29, <<transition_id::16, commit::binary>>, now) do
    case process_commit(session, commit) do
      {:ok, group} ->
        install(session, group, transition_id, now)

      :ignore ->
        {session, []}

      {:error, reason} ->
        Logger.warning("Lingo DAVE rejected a commit: #{inspect(reason)}")
        recover(session, transition_id, now)
    end
  end

  def handle_binary(session, 30, <<transition_id::16, welcome::binary>>, now) do
    case process_welcome(session, welcome) do
      {:ok, group} ->
        install(session, group, transition_id, now)

      {:error, reason} ->
        Logger.warning("Lingo DAVE rejected a welcome: #{inspect(reason)}")
        recover(session, transition_id, now)
    end
  end

  def handle_binary(session, _op, _payload, _now), do: {session, []}

  ## Media

  @doc "Encrypts an outgoing Opus frame, or passes it through when DAVE is off."
  @spec encrypt(t(), binary()) :: {:ok, binary(), t()} | {:error, :not_ready}
  def encrypt(%{protocol_version: 0} = session, frame), do: {:ok, frame, session}

  def encrypt(session, frame) do
    cond do
      frame == Frame.silence() ->
        {:ok, frame, session}

      session.encryptor == nil ->
        {:error, :not_ready}

      true ->
        case Encryptor.encrypt(session.encryptor, frame) do
          {:ok, encrypted, encryptor} -> {:ok, encrypted, %{session | encryptor: encryptor}}
          :error -> {:error, :not_ready}
        end
    end
  end

  @spec decrypt(t(), non_neg_integer(), binary(), integer()) ::
          {:ok, binary(), t()} | {:error, atom(), t()}
  def decrypt(session, user_id, frame, now) do
    decryptor = Map.get_lazy(session.decryptors, user_id, fn -> new_decryptor(session, now) end)

    case Decryptor.decrypt(decryptor, frame, now) do
      {:ok, plaintext, decryptor} ->
        {:ok, plaintext, put_in(session.decryptors[user_id], decryptor)}

      {:error, reason, decryptor} ->
        {:error, reason, put_in(session.decryptors[user_id], decryptor)}
    end
  end

  defp new_decryptor(session, now) do
    if session.passthrough,
      do: Decryptor.passthrough(Decryptor.new(), true, now),
      else: Decryptor.new()
  end

  ## (Re)initialization

  # starts over waiting to be added: a fresh leaf, a fresh pending group and a
  # new key package, or plain passthrough when DAVE is off
  defp reinit(%{protocol_version: 0} = session, now) do
    session = reset(session)
    {%{passthrough(session, true, now) | encryptor: nil, pending_encryptor: nil}, []}
  end

  defp reinit(session, _now) do
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

  defp reset(session) do
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

  defp create_pending_group(
         %{external_sender: sender, leaf: {leaf, encryption_private_key}} = session
       )
       when sender != nil do
    {_signature_key, signature_private_key} = session.signature_key

    extensions = [
      {Message.extension_external_senders(), encode(Message.encode_external_senders([sender]))}
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

  defp create_pending_group(session), do: session

  # our MLS group is identified by the channel id, as a big-endian uint64
  defp group_id(session), do: <<session.channel_id::64>>

  defp recognized_users(session), do: MapSet.put(session.connected, session.user_id)

  ## Proposals and commits

  defp process_proposals(session, revoke?, payload) do
    base = session.staged || session.pending_group || session.group

    with :ok <- check(base != nil, :no_group),
         {:ok, staged} <- apply_proposals(session, base, revoke?, payload),
         {:ok, commit, welcome, outbound} <- Group.commit(staged) do
      session = %{session | staged: staged, pending_commit: commit, outbound: outbound}
      {:ok, session, [{:binary, 28, commit <> (welcome || <<>>)}]}
    end
  end

  defp apply_proposals(_session, staged, true, payload) do
    with {:ok, refs} <-
           Message.decode(payload, &Codec.decode_list(&1, fn bin -> Codec.decode_vector(bin) end)) do
      Group.revoke(staged, refs)
    end
  end

  defp apply_proposals(session, staged, false, payload) do
    with {:ok, messages} <-
           Message.decode(payload, &Codec.decode_list(&1, fn bin -> raw_mls_message(bin) end)) do
      Enum.reduce_while(messages, {:ok, staged}, fn message, {:ok, staged} ->
        with {:ok, next, entry} <- Group.handle_proposal(staged, message),
             :ok <- allowed_proposal?(session, entry) do
          {:cont, {:ok, next}}
        else
          error -> {:halt, error}
        end
      end)
    end
  end

  # splits one MLSMessage off the front of a binary, keeping its raw bytes
  defp raw_mls_message(binary) do
    {_message, rest} = Message.decode_mls_message(binary)
    {binary_part(binary, 0, byte_size(binary) - byte_size(rest)), rest}
  end

  # only the gateway may propose, only adds and removes, and only adds for
  # users we know are in the call
  defp allowed_proposal?(session, %{sender: {:external, _index}, proposal: proposal}) do
    case proposal do
      {:add, key_package} ->
        check(user_id(key_package.leaf_node) in recognized_users(session), :unexpected_user)

      {:remove, _leaf_index} ->
        :ok

      _other ->
        {:error, :unexpected_proposal}
    end
  end

  defp allowed_proposal?(_session, _entry), do: {:error, :unexpected_proposal}

  defp process_commit(%{staged: nil, group: nil}, _commit), do: :ignore
  defp process_commit(%{staged: nil}, _commit), do: {:error, :no_proposals}

  defp process_commit(session, commit) do
    initial? = commit == session.pending_commit

    with :ok <- check(session.group != nil or initial?, :unexpected_commit),
         {:ok, {:public_message, %{content: content}}} <-
           Message.decode(commit, &Message.decode_mls_message/1),
         :ok <- check(content.group_id == group_id(session), :wrong_group),
         {:commit, %{proposals: proposals}} <- content.content,
         :ok <- check(Enum.all?(proposals, &match?({:reference, _}, &1)), :proposal_by_value),
         {:ok, group} <- Group.handle_commit(session.staged, commit, session.outbound),
         :ok <- check(unique_users?(group), :duplicate_user) do
      {:ok, group}
    else
      {:error, reason} -> {:error, reason}
      _unexpected -> {:error, :invalid_commit}
    end
  end

  defp process_welcome(session, welcome) do
    with :ok <- check(session.group == nil, :already_joined),
         {:ok, {key_package, init_private_key}} <- fetch(session.key_package, :no_key_package),
         {:ok, {_leaf, encryption_private_key}} <- fetch(session.leaf, :no_leaf),
         {:ok, sender} <- fetch(session.external_sender, :no_external_sender),
         {_signature_key, signature_private_key} = session.signature_key,
         {:ok, group} <-
           Group.join(
             welcome,
             key_package,
             init_private_key,
             encryption_private_key,
             signature_private_key
           ),
         :ok <- check(group.group_id == group_id(session), :wrong_group),
         :ok <- check(Group.external_senders(group) == [sender], :wrong_external_sender),
         :ok <- check(unique_users?(group), :duplicate_user),
         :ok <-
           check(Enum.all?(users(group), &(&1 in recognized_users(session))), :unexpected_user) do
      {:ok, group}
    end
  end

  # starts using a new group: receivers switch keys now, senders once the
  # transition executes
  defp install(session, group, transition_id, now) do
    decryptors =
      for user_id <- users(group), user_id != session.user_id, into: session.decryptors do
        decryptor =
          Map.get_lazy(session.decryptors, user_id, fn -> new_decryptor(session, now) end)

        {user_id, Decryptor.add_ratchet(decryptor, KeyRatchet.new(group, user_id), now)}
      end

    session = %{
      session
      | group: group,
        decryptors: decryptors,
        pending_encryptor: Encryptor.new(KeyRatchet.new(group, session.user_id)),
        pending_group: nil,
        pending_commit: nil,
        staged: nil,
        outbound: nil,
        key_package: nil
    }

    if transition_id == 0 do
      execute_transition(put_in(session.transitions[0], session.protocol_version), 0, now)
    else
      session = put_in(session.transitions[transition_id], session.protocol_version)
      {session, [ready(transition_id)]}
    end
  end

  defp execute_transition(session, transition_id, now) do
    case Map.pop(session.transitions, transition_id) do
      {nil, _transitions} ->
        {session, []}

      {0, transitions} ->
        session = %{session | transitions: transitions, protocol_version: 0, encryptor: nil}
        {passthrough(session, true, now), []}

      {version, transitions} ->
        session = %{session | transitions: transitions, protocol_version: version}

        session =
          if session.pending_encryptor,
            do: %{session | encryptor: session.pending_encryptor, pending_encryptor: nil},
            else: session

        # stop accepting plaintext once in-flight media is through
        {passthrough(session, false, now, @transition_expiry), []}
    end
  end

  # flags the transition as broken and starts over with a new key package
  defp recover(session, transition_id, now) do
    {session, messages} = reinit(session, now)
    {session, [{:json, 31, %{transition_id: transition_id}} | messages]}
  end

  defp passthrough(session, allow?, now, expiry \\ @transition_expiry) do
    decryptors =
      Map.new(session.decryptors, fn {id, d} ->
        {id, Decryptor.passthrough(d, allow?, now, expiry)}
      end)

    %{session | decryptors: decryptors, passthrough: allow?}
  end

  defp ready(transition_id), do: {:json, 23, %{transition_id: transition_id}}

  ## Helpers

  defp users(group), do: Enum.map(Group.roster(group), fn {_index, leaf} -> user_id(leaf) end)

  defp unique_users?(group), do: length(Enum.uniq(users(group))) == length(users(group))

  defp user_id(%LeafNode{credential: {:basic, <<user_id::64>>}}), do: user_id
  defp user_id(_leaf), do: nil

  defp encode(iodata), do: IO.iodata_to_binary(iodata)

  defp check(true, _reason), do: :ok
  defp check(false, reason), do: {:error, reason}

  defp fetch(nil, reason), do: {:error, reason}
  defp fetch(value, _reason), do: {:ok, value}
end
