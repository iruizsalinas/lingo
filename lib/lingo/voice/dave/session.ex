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

  alias Lingo.MLS.{Crypto, Group, Message, Welcome}
  alias Lingo.Voice.Dave.{Decryptor, Encryptor, Frame}

  require Logger

  # how long receivers keep accepting unencrypted media after a downgrade
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

  alias Lingo.Voice.Dave.Session.{Proposals, Setup, Transition}

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

  @doc "The protocol version from the session description (op 4)."
  @spec set_protocol_version(t(), non_neg_integer(), integer()) :: {t(), [message()]}
  def set_protocol_version(session, version, now),
    do: Setup.reinit(%{session | protocol_version: version}, now)

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
        Transition.execute_transition(session, 0, now)

      version == 0 ->
        {Transition.passthrough(session, true, now, @downgrade_expiry),
         [Transition.ready(transition_id)]}

      true ->
        {session, [Transition.ready(transition_id)]}
    end
  end

  def handle_json(session, 22, %{"transition_id" => transition_id}, now),
    do: Transition.execute_transition(session, transition_id, now)

  def handle_json(session, 24, %{"epoch" => 1, "protocol_version" => version}, now),
    do: Setup.reinit(%{session | protocol_version: version}, now)

  def handle_json(session, _op, _data, _now), do: {session, []}

  @doc "Handles a binary DAVE opcode (25, 27, 29 and 30); `payload` follows the opcode byte."
  @spec handle_binary(t(), non_neg_integer(), binary(), integer()) :: {t(), [message()]}
  def handle_binary(session, 25, payload, _now) do
    case Message.decode(payload, &Welcome.decode_external_sender/1) do
      {:ok, sender} when session.group == nil ->
        {Setup.create_pending_group(%{session | external_sender: sender}), []}

      _invalid_or_too_late ->
        Logger.warning("Lingo DAVE ignored an external sender package")
        {session, []}
    end
  end

  def handle_binary(session, 27, <<revoke, payload::binary>>, _now) when revoke in [0, 1] do
    case Proposals.process_proposals(session, revoke == 1, payload) do
      {:ok, session, messages} ->
        {session, messages}

      {:error, reason} ->
        Logger.warning("Lingo DAVE could not process proposals: #{inspect(reason)}")
        {session, []}
    end
  end

  def handle_binary(session, 29, <<transition_id::16, commit::binary>>, now) do
    case Proposals.process_commit(session, commit) do
      {:ok, group} ->
        Transition.install(session, group, transition_id, now)

      :ignore ->
        {session, []}

      {:error, reason} ->
        Logger.warning("Lingo DAVE rejected a commit: #{inspect(reason)}")
        Transition.recover(session, transition_id, now)
    end
  end

  def handle_binary(session, 30, <<transition_id::16, welcome::binary>>, now) do
    case Proposals.process_welcome(session, welcome) do
      {:ok, group} ->
        Transition.install(session, group, transition_id, now)

      {:error, reason} ->
        Logger.warning("Lingo DAVE rejected a welcome: #{inspect(reason)}")
        Transition.recover(session, transition_id, now)
    end
  end

  def handle_binary(session, _op, _payload, _now), do: {session, []}

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
    decryptor =
      Map.get_lazy(session.decryptors, user_id, fn -> Transition.new_decryptor(session, now) end)

    case Decryptor.decrypt(decryptor, frame, now) do
      {:ok, plaintext, decryptor} ->
        {:ok, plaintext, put_in(session.decryptors[user_id], decryptor)}

      {:error, reason, decryptor} ->
        {:error, reason, put_in(session.decryptors[user_id], decryptor)}
    end
  end
end
