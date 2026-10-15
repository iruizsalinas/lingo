defmodule Lingo.Voice.Dave.Session.Proposals do
  @moduledoc false

  # Proposals, commits and welcomes from the voice gateway (ops 27, 29 and 30).

  alias Lingo.MLS.{Codec, Group, Message}
  alias Lingo.Voice.Dave.Session.{Setup, Util}

  def process_proposals(session, revoke?, payload) do
    base = session.staged || session.pending_group || session.group

    with :ok <- Util.check(base != nil, :no_group),
         {:ok, staged} <- apply_proposals(session, base, revoke?, payload),
         {:ok, commit, welcome, outbound} <- Group.commit(staged) do
      session = %{session | staged: staged, pending_commit: commit, outbound: outbound}
      {:ok, session, [{:binary, 28, commit <> (welcome || <<>>)}]}
    end
  end

  def apply_proposals(_session, staged, true, payload) do
    with {:ok, refs} <-
           Message.decode(payload, &Codec.decode_list(&1, fn bin -> Codec.decode_vector(bin) end)) do
      Group.revoke(staged, refs)
    end
  end

  def apply_proposals(session, staged, false, payload) do
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
  def raw_mls_message(binary) do
    {_message, rest} = Message.decode_mls_message(binary)
    {binary_part(binary, 0, byte_size(binary) - byte_size(rest)), rest}
  end

  # only the gateway may propose, only adds and removes, and only adds for
  # users we know are in the call
  def allowed_proposal?(session, %{sender: {:external, _index}, proposal: proposal}) do
    case proposal do
      {:add, key_package} ->
        Util.check(
          Util.user_id(key_package.leaf_node) in Setup.recognized_users(session),
          :unexpected_user
        )

      {:remove, _leaf_index} ->
        :ok

      _other ->
        {:error, :unexpected_proposal}
    end
  end

  def allowed_proposal?(_session, _entry), do: {:error, :unexpected_proposal}

  def process_commit(%{staged: nil, group: nil}, _commit), do: :ignore
  def process_commit(%{staged: nil}, _commit), do: {:error, :no_proposals}

  def process_commit(session, commit) do
    initial? = commit == session.pending_commit

    with :ok <- Util.check(session.group != nil or initial?, :unexpected_commit),
         {:ok, {:public_message, %{content: content}}} <-
           Message.decode(commit, &Message.decode_mls_message/1),
         :ok <- Util.check(content.group_id == Setup.group_id(session), :wrong_group),
         {:commit, %{proposals: proposals}} <- content.content,
         :ok <-
           Util.check(Enum.all?(proposals, &match?({:reference, _}, &1)), :proposal_by_value),
         {:ok, group} <- Group.handle_commit(session.staged, commit, session.outbound),
         :ok <- Util.check(Util.unique_users?(group), :duplicate_user) do
      {:ok, group}
    else
      {:error, reason} -> {:error, reason}
      _unexpected -> {:error, :invalid_commit}
    end
  end

  def process_welcome(session, welcome) do
    with :ok <- Util.check(session.group == nil, :already_joined),
         {:ok, {key_package, init_private_key}} <-
           Util.fetch(session.key_package, :no_key_package),
         {:ok, {_leaf, encryption_private_key}} <- Util.fetch(session.leaf, :no_leaf),
         {:ok, sender} <- Util.fetch(session.external_sender, :no_external_sender),
         {_signature_key, signature_private_key} = session.signature_key,
         {:ok, group} <-
           Group.join(
             welcome,
             key_package,
             init_private_key,
             encryption_private_key,
             signature_private_key
           ),
         :ok <- Util.check(group.group_id == Setup.group_id(session), :wrong_group),
         :ok <- Util.check(Group.external_senders(group) == [sender], :wrong_external_sender),
         :ok <- Util.check(Util.unique_users?(group), :duplicate_user),
         :ok <-
           Util.check(
             Enum.all?(Util.users(group), &(&1 in Setup.recognized_users(session))),
             :unexpected_user
           ) do
      {:ok, group}
    end
  end
end
