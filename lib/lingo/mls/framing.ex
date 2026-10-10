defmodule Lingo.MLS.Framing do
  @moduledoc false

  # Framing: senders, framed content, PublicMessage and what gets signed and
  # MAC'd (RFC 9420, section 6).

  alias Lingo.MLS.{Codec, Commit, Message}

  @version 1

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

  def encode_sender({:member, leaf_index}), do: <<1, leaf_index::32>>
  def encode_sender({:external, sender_index}), do: <<2, sender_index::32>>
  def encode_sender(:new_member_proposal), do: <<3>>
  def encode_sender(:new_member_commit), do: <<4>>

  def encode_content({:application, data}), do: [<<1>>, Codec.vector(data)]
  def encode_content({:proposal, proposal}), do: [<<2>>, Message.encode_proposal(proposal)]
  def encode_content({:commit, commit}), do: [<<3>>, Commit.encode_commit(commit)]

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

  def decode_sender(<<1, leaf_index::32, rest::binary>>), do: {{:member, leaf_index}, rest}
  def decode_sender(<<2, sender_index::32, rest::binary>>), do: {{:external, sender_index}, rest}
  def decode_sender(<<3, rest::binary>>), do: {:new_member_proposal, rest}
  def decode_sender(<<4, rest::binary>>), do: {:new_member_commit, rest}

  def decode_content(<<1, rest::binary>>) do
    {data, rest} = Codec.decode_vector(rest)
    {{:application, data}, rest}
  end

  def decode_content(<<2, rest::binary>>) do
    {proposal, rest} = Message.decode_proposal(rest)
    {{:proposal, proposal}, rest}
  end

  def decode_content(<<3, rest::binary>>) do
    {commit, rest} = Commit.decode_commit(rest)
    {{:commit, commit}, rest}
  end

  def encode_public_message(message) do
    [
      encode_framed_content(message.content),
      encode_auth_data(message),
      if(member_sender?(message.content), do: Codec.vector(message.membership_tag), else: [])
    ]
  end

  def decode_public_message(binary) do
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

  def encode_auth_data(message) do
    [
      Codec.vector(message.signature),
      if(commit?(message.content), do: Codec.vector(message.confirmation_tag), else: [])
    ]
  end

  def commit?(content), do: match?({:commit, _commit}, content.content)

  def member_sender?(content), do: match?({:member, _index}, content.sender)

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
end
