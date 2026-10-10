defmodule Lingo.MLS.Welcome do
  @moduledoc false

  # Group state for joining: GroupContext, GroupInfo, GroupSecrets, Welcome
  # and external senders (RFC 9420, sections 8.1, 12.1.8.1 and 12.4.3).

  alias Lingo.MLS.{Codec, Commit, LeafNode}

  @version 1

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
          Commit.encode_hpke_ciphertext({secret.kem_output, secret.ciphertext})
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
        {{kem_output, ciphertext}, rest} = Commit.decode_hpke_ciphertext(rest)
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
