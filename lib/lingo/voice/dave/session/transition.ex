defmodule Lingo.Voice.Dave.Session.Transition do
  @moduledoc false

  # Switching to new keys: receivers right away, senders once the transition executes.

  # how long receivers keep accepting unencrypted media around a downgrade
  @transition_expiry 10_000

  alias Lingo.Voice.Dave.{Decryptor, Encryptor, KeyRatchet}
  alias Lingo.Voice.Dave.Session.{Setup, Util}

  def new_decryptor(session, now) do
    if session.passthrough,
      do: Decryptor.passthrough(Decryptor.new(), true, now),
      else: Decryptor.new()
  end

  # starts using a new group: receivers switch keys now, senders once the
  # transition executes
  def install(session, group, transition_id, now) do
    decryptors =
      for user_id <- Util.users(group), user_id != session.user_id, into: session.decryptors do
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

  def execute_transition(session, transition_id, now) do
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
  def recover(session, transition_id, now) do
    {session, messages} = Setup.reinit(session, now)
    {session, [{:json, 31, %{transition_id: transition_id}} | messages]}
  end

  def passthrough(session, allow?, now, expiry \\ @transition_expiry) do
    decryptors =
      Map.new(session.decryptors, fn {id, d} ->
        {id, Decryptor.passthrough(d, allow?, now, expiry)}
      end)

    %{session | decryptors: decryptors, passthrough: allow?}
  end

  def ready(transition_id), do: {:json, 23, %{transition_id: transition_id}}
end
