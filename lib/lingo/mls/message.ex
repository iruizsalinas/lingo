defmodule Lingo.MLS.Message do
  @moduledoc false

  # Wire formats for proposals, commits, framing and joining (RFC 9420,
  # sections 6, 12 and 12.4.3). Structures are plain maps; the encodings are
  # canonical, so decoding and re-encoding reproduces the signed bytes.
  #
  # Only what DAVE and the passive client vectors need is supported: public
  # messages (no PrivateMessage) and Add, Update and Remove proposals.

  alias Lingo.MLS.{Codec, Framing, KeyPackage, LeafNode, Welcome}

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

  defp encode_body(:public_message, message), do: Framing.encode_public_message(message)
  defp encode_body(:welcome, welcome), do: Welcome.encode_welcome(welcome)
  defp encode_body(:group_info, group_info), do: Welcome.encode_group_info(group_info)
  defp encode_body(:key_package, key_package), do: KeyPackage.encode(key_package)

  @spec decode_mls_message(binary()) :: {{atom(), term()}, binary()}
  def decode_mls_message(<<@version::16, 1::16, rest::binary>>),
    do: wrap(:public_message, Framing.decode_public_message(rest))

  def decode_mls_message(<<@version::16, 3::16, rest::binary>>),
    do: wrap(:welcome, Welcome.decode_welcome(rest))

  def decode_mls_message(<<@version::16, 4::16, rest::binary>>),
    do: wrap(:group_info, Welcome.decode_group_info(rest))

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

  ## Framing (RFC 9420, section 6)

  # A PublicMessage: the content, its signature, a confirmation tag for
  # commits and a membership tag for members.

  ## Group state (RFC 9420, sections 8.1 and 12.4.3)

  ## External senders (RFC 9420, section 12.1.8.1)
end
