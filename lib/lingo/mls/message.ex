defmodule Lingo.MLS.Message do
  @moduledoc false

  # Wire formats for proposals, commits, framing and joining (RFC 9420,
  # sections 6, 12 and 12.4.3). Structures are plain maps; the encodings are
  # canonical, so decoding and re-encoding reproduces the signed bytes.
  #
  # Only what DAVE and the passive client vectors need is supported: public
  # messages (no PrivateMessage) and Add, Update and Remove proposals.

  alias Lingo.MLS.{Codec, KeyPackage, LeafNode}

  @version 1

  @wire_formats %{public_message: 1, welcome: 3, group_info: 4, key_package: 5}

  @extension_ratchet_tree 2
  @extension_external_senders 5

  def extension_ratchet_tree, do: @extension_ratchet_tree
  def extension_external_senders, do: @extension_external_senders

  @doc "Decodes a whole binary with `decode`, turning malformed input into an error."
  @spec decode(binary(), (binary() -> {term(), binary()})) :: {:ok, term()} | {:error, :malformed}
  def decode(binary, decode) do
    {:ok, Codec.decode_exact(binary, decode)}
  rescue
    _error in [ArgumentError, MatchError, FunctionClauseError, CaseClauseError] ->
      {:error, :malformed}
  end

  ## MLSMessage

  @spec encode_mls_message({atom(), term()}) :: iodata()
  def encode_mls_message({wire_format, body}) do
    [<<@version::16, Map.fetch!(@wire_formats, wire_format)::16>>, encode_body(wire_format, body)]
  end

  defp encode_body(:public_message, message), do: encode_public_message(message)
  defp encode_body(:welcome, welcome), do: encode_welcome(welcome)
  defp encode_body(:group_info, group_info), do: encode_group_info(group_info)
  defp encode_body(:key_package, key_package), do: KeyPackage.encode(key_package)

  @spec decode_mls_message(binary()) :: {{atom(), term()}, binary()}
  def decode_mls_message(<<@version::16, 1::16, rest::binary>>),
    do: wrap(:public_message, decode_public_message(rest))

  def decode_mls_message(<<@version::16, 3::16, rest::binary>>),
    do: wrap(:welcome, decode_welcome(rest))

  def decode_mls_message(<<@version::16, 4::16, rest::binary>>),
    do: wrap(:group_info, decode_group_info(rest))

  def decode_mls_message(<<@version::16, 5::16, rest::binary>>),
    do: wrap(:key_package, KeyPackage.decode(rest))

  def decode_mls_message(_binary), do: raise(ArgumentError, "unsupported MLS message")

  defp wrap(wire_format, {body, rest}), do: {{wire_format, body}, rest}

  ## Proposals (RFC 9420, section 12.1)

  @spec encode_proposal(tuple()) :: iodata()
  def encode_proposal({:add, key_package}), do: [<<1::16>>, KeyPackage.encode(key_package)]
  def encode_proposal({:update, leaf}), do: [<<2::16>>, LeafNode.encode(leaf)]
  def encode_proposal({:remove, leaf_index}), do: <<3::16, leaf_index::32>>

  @spec decode_proposal(binary()) :: {tuple(), binary()}
  def decode_proposal(<<1::16, rest::binary>>) do
    {key_package, rest} = KeyPackage.decode(rest)
    {{:add, key_package}, rest}
  end

  def decode_proposal(<<2::16, rest::binary>>) do
    {leaf, rest} = LeafNode.decode(rest)
    {{:update, leaf}, rest}
  end

  def decode_proposal(<<3::16, leaf_index::32, rest::binary>>), do: {{:remove, leaf_index}, rest}
  def decode_proposal(_binary), do: raise(ArgumentError, "unsupported proposal type")

  ## Commit and UpdatePath (RFC 9420, sections 7.6 and 12.4)

  @spec encode_commit(map()) :: iodata()
  def encode_commit(commit) do
    [
      Codec.list(commit.proposals, &encode_proposal_or_ref/1),
      Codec.optional(commit.path, &encode_update_path/1)
    ]
  end

  defp encode_proposal_or_ref({:proposal, proposal}), do: [<<1>>, encode_proposal(proposal)]
  defp encode_proposal_or_ref({:reference, ref}), do: [<<2>>, Codec.vector(ref)]

  defp encode_update_path(path) do
    [
      LeafNode.encode(path.leaf_node),
      Codec.list(path.nodes, fn node ->
        [
          Codec.vector(node.encryption_key),
          Codec.list(node.ciphertexts, &encode_hpke_ciphertext/1)
        ]
      end)
    ]
  end

  defp encode_hpke_ciphertext({kem_output, ciphertext}),
    do: [Codec.vector(kem_output), Codec.vector(ciphertext)]

  @spec decode_commit(binary()) :: {map(), binary()}
  def decode_commit(binary) do
    {proposals, rest} = Codec.decode_list(binary, &decode_proposal_or_ref/1)
    {path, rest} = Codec.decode_optional(rest, &decode_update_path/1)
    {%{proposals: proposals, path: path}, rest}
  end

  defp decode_proposal_or_ref(<<1, rest::binary>>) do
    {proposal, rest} = decode_proposal(rest)
    {{:proposal, proposal}, rest}
  end

  defp decode_proposal_or_ref(<<2, rest::binary>>) do
    {ref, rest} = Codec.decode_vector(rest)
    {{:reference, ref}, rest}
  end

  @spec decode_update_path(binary()) :: {map(), binary()}
  def decode_update_path(binary) do
    {leaf_node, rest} = LeafNode.decode(binary)

    {nodes, rest} =
      Codec.decode_list(rest, fn binary ->
        {encryption_key, rest} = Codec.decode_vector(binary)
        {ciphertexts, rest} = Codec.decode_list(rest, &decode_hpke_ciphertext/1)
        {%{encryption_key: encryption_key, ciphertexts: ciphertexts}, rest}
      end)

    {%{leaf_node: leaf_node, nodes: nodes}, rest}
  end

  defp decode_hpke_ciphertext(binary) do
    {kem_output, rest} = Codec.decode_vector(binary)
    {ciphertext, rest} = Codec.decode_vector(rest)
    {{kem_output, ciphertext}, rest}
  end

  ## Framing (RFC 9420, section 6)

  @spec encode_framed_content(map()) :: iodata()
  def encode_framed_content(content) do
    [
      Codec.vector(content.group_id),
      <<content.epoch::64>>,
      encode_sender(content.sender),
      Codec.vector(content.authenticated_data),
      encode_content(content.content)
    ]
  end

  defp encode_sender({:member, leaf_index}), do: <<1, leaf_index::32>>
  defp encode_sender({:external, sender_index}), do: <<2, sender_index::32>>
  defp encode_sender(:new_member_proposal), do: <<3>>
  defp encode_sender(:new_member_commit), do: <<4>>

  defp encode_content({:application, data}), do: [<<1>>, Codec.vector(data)]
  defp encode_content({:proposal, proposal}), do: [<<2>>, encode_proposal(proposal)]
  defp encode_content({:commit, commit}), do: [<<3>>, encode_commit(commit)]

  @spec decode_framed_content(binary()) :: {map(), binary()}
  def decode_framed_content(binary) do
    {group_id, <<epoch::64, rest::binary>>} = Codec.decode_vector(binary)
    {sender, rest} = decode_sender(rest)
    {authenticated_data, rest} = Codec.decode_vector(rest)
    {content, rest} = decode_content(rest)

    framed = %{
      group_id: group_id,
      epoch: epoch,
      sender: sender,
      authenticated_data: authenticated_data,
      content: content
    }

    {framed, rest}
  end

  defp decode_sender(<<1, leaf_index::32, rest::binary>>), do: {{:member, leaf_index}, rest}
  defp decode_sender(<<2, sender_index::32, rest::binary>>), do: {{:external, sender_index}, rest}
  defp decode_sender(<<3, rest::binary>>), do: {:new_member_proposal, rest}
  defp decode_sender(<<4, rest::binary>>), do: {:new_member_commit, rest}

  defp decode_content(<<1, rest::binary>>) do
    {data, rest} = Codec.decode_vector(rest)
    {{:application, data}, rest}
  end

  defp decode_content(<<2, rest::binary>>) do
    {proposal, rest} = decode_proposal(rest)
    {{:proposal, proposal}, rest}
  end

  defp decode_content(<<3, rest::binary>>) do
    {commit, rest} = decode_commit(rest)
    {{:commit, commit}, rest}
  end

  # A PublicMessage: the content, its signature, a confirmation tag for
  # commits and a membership tag for members.

  defp encode_public_message(message) do
    [
      encode_framed_content(message.content),
      encode_auth_data(message),
      if(member_sender?(message.content), do: Codec.vector(message.membership_tag), else: [])
    ]
  end

  defp decode_public_message(binary) do
    {content, rest} = decode_framed_content(binary)
    {signature, rest} = Codec.decode_vector(rest)

    {confirmation_tag, rest} =
      if commit?(content), do: Codec.decode_vector(rest), else: {nil, rest}

    {membership_tag, rest} =
      if member_sender?(content), do: Codec.decode_vector(rest), else: {nil, rest}

    message = %{
      content: content,
      signature: signature,
      confirmation_tag: confirmation_tag,
      membership_tag: membership_tag
    }

    {message, rest}
  end

  defp encode_auth_data(message) do
    [
      Codec.vector(message.signature),
      if(commit?(message.content), do: Codec.vector(message.confirmation_tag), else: [])
    ]
  end

  defp commit?(content), do: match?({:commit, _commit}, content.content)
  defp member_sender?(content), do: match?({:member, _index}, content.sender)

  @doc "FramedContentTBS: what the sender signs, bound to the group context for members."
  @spec framed_content_tbs(map(), binary()) :: iodata()
  def framed_content_tbs(content, group_context) do
    context =
      case content.sender do
        {:member, _index} -> group_context
        :new_member_commit -> group_context
        _other -> []
      end

    [<<@version::16, 1::16>>, encode_framed_content(content), context]
  end

  @doc "AuthenticatedContentTBM: what the membership tag covers."
  @spec membership_tag_input(map(), binary()) :: iodata()
  def membership_tag_input(message, group_context),
    do: [framed_content_tbs(message.content, group_context), encode_auth_data(message)]

  @doc "AuthenticatedContent: what a proposal reference hashes."
  @spec authenticated_content(map()) :: iodata()
  def authenticated_content(message),
    do: [<<1::16>>, encode_framed_content(message.content), encode_auth_data(message)]

  @spec confirmed_transcript_input(map()) :: iodata()
  def confirmed_transcript_input(message),
    do: [<<1::16>>, encode_framed_content(message.content), Codec.vector(message.signature)]

  ## Group state (RFC 9420, sections 8.1 and 12.4.3)

  @spec encode_group_context(map()) :: iodata()
  def encode_group_context(context) do
    [
      <<@version::16, context.cipher_suite::16>>,
      Codec.vector(context.group_id),
      <<context.epoch::64>>,
      Codec.vector(context.tree_hash),
      Codec.vector(context.confirmed_transcript_hash),
      Codec.extensions(context.extensions)
    ]
  end

  @spec decode_group_context(binary()) :: {map(), binary()}
  def decode_group_context(<<@version::16, cipher_suite::16, rest::binary>>) do
    {group_id, <<epoch::64, rest::binary>>} = Codec.decode_vector(rest)
    {tree_hash, rest} = Codec.decode_vector(rest)
    {confirmed_transcript_hash, rest} = Codec.decode_vector(rest)
    {extensions, rest} = Codec.decode_extensions(rest)

    context = %{
      cipher_suite: cipher_suite,
      group_id: group_id,
      epoch: epoch,
      tree_hash: tree_hash,
      confirmed_transcript_hash: confirmed_transcript_hash,
      extensions: extensions
    }

    {context, rest}
  end

  @spec encode_group_info_tbs(map()) :: iodata()
  def encode_group_info_tbs(group_info) do
    [
      encode_group_context(group_info.group_context),
      Codec.extensions(group_info.extensions),
      Codec.vector(group_info.confirmation_tag),
      <<group_info.signer::32>>
    ]
  end

  @spec encode_group_info(map()) :: iodata()
  def encode_group_info(group_info),
    do: [encode_group_info_tbs(group_info), Codec.vector(group_info.signature)]

  @spec decode_group_info(binary()) :: {map(), binary()}
  def decode_group_info(binary) do
    {group_context, rest} = decode_group_context(binary)
    {extensions, rest} = Codec.decode_extensions(rest)
    {confirmation_tag, <<signer::32, rest::binary>>} = Codec.decode_vector(rest)
    {signature, rest} = Codec.decode_vector(rest)

    group_info = %{
      group_context: group_context,
      extensions: extensions,
      confirmation_tag: confirmation_tag,
      signer: signer,
      signature: signature
    }

    {group_info, rest}
  end

  @spec encode_group_secrets(map()) :: iodata()
  def encode_group_secrets(secrets) do
    [
      Codec.vector(secrets.joiner_secret),
      Codec.optional(secrets.path_secret, &Codec.vector/1),
      # no pre-shared keys
      Codec.vector(<<>>)
    ]
  end

  @spec decode_group_secrets(binary()) :: {map(), binary()}
  def decode_group_secrets(binary) do
    {joiner_secret, rest} = Codec.decode_vector(binary)
    {path_secret, rest} = Codec.decode_optional(rest, &Codec.decode_vector/1)

    case Codec.decode_vector(rest) do
      {<<>>, rest} -> {%{joiner_secret: joiner_secret, path_secret: path_secret}, rest}
      _psks -> raise ArgumentError, "pre-shared keys are not supported"
    end
  end

  @spec encode_welcome(map()) :: iodata()
  def encode_welcome(welcome) do
    [
      <<welcome.cipher_suite::16>>,
      Codec.list(welcome.secrets, fn secret ->
        [
          Codec.vector(secret.new_member),
          encode_hpke_ciphertext({secret.kem_output, secret.ciphertext})
        ]
      end),
      Codec.vector(welcome.encrypted_group_info)
    ]
  end

  @spec decode_welcome(binary()) :: {map(), binary()}
  def decode_welcome(<<cipher_suite::16, rest::binary>>) do
    {secrets, rest} =
      Codec.decode_list(rest, fn binary ->
        {new_member, rest} = Codec.decode_vector(binary)
        {{kem_output, ciphertext}, rest} = decode_hpke_ciphertext(rest)
        {%{new_member: new_member, kem_output: kem_output, ciphertext: ciphertext}, rest}
      end)

    {encrypted_group_info, rest} = Codec.decode_vector(rest)

    welcome = %{
      cipher_suite: cipher_suite,
      secrets: secrets,
      encrypted_group_info: encrypted_group_info
    }

    {welcome, rest}
  end

  ## External senders (RFC 9420, section 12.1.8.1)

  @spec encode_external_sender(map()) :: iodata()
  def encode_external_sender(sender),
    do: [Codec.vector(sender.signature_key), LeafNode.encode_credential(sender.credential)]

  @spec decode_external_sender(binary()) :: {map(), binary()}
  def decode_external_sender(binary) do
    {signature_key, rest} = Codec.decode_vector(binary)
    {credential, rest} = LeafNode.decode_credential(rest)
    {%{signature_key: signature_key, credential: credential}, rest}
  end

  @spec encode_external_senders([map()]) :: iodata()
  def encode_external_senders(senders), do: Codec.list(senders, &encode_external_sender/1)

  @spec decode_external_senders(binary()) :: {[map()], binary()}
  def decode_external_senders(binary), do: Codec.decode_list(binary, &decode_external_sender/1)
end
