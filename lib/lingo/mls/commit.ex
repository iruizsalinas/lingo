defmodule Lingo.MLS.Commit do
  @moduledoc false

  # Commit and UpdatePath (RFC 9420, sections 7.6 and 12.4).

  alias Lingo.MLS.{Codec, LeafNode, Message}

  @spec encode_commit(map()) :: iodata()
  def encode_commit(commit) do
    [
      Codec.list(commit.proposals, &encode_proposal_or_ref/1),
      Codec.optional(commit.path, &encode_update_path/1)
    ]
  end

  def encode_proposal_or_ref({:proposal, proposal}),
    do: [<<1>>, Message.encode_proposal(proposal)]

  def encode_proposal_or_ref({:reference, ref}), do: [<<2>>, Codec.vector(ref)]

  def encode_update_path(path) do
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

  def encode_hpke_ciphertext({kem_output, ciphertext}),
    do: [Codec.vector(kem_output), Codec.vector(ciphertext)]

  @spec decode_commit(binary()) :: {map(), binary()}
  def decode_commit(binary) do
    {proposals, rest} = Codec.decode_list(binary, &decode_proposal_or_ref/1)
    {path, rest} = Codec.decode_optional(rest, &decode_update_path/1)
    {%{proposals: proposals, path: path}, rest}
  end

  def decode_proposal_or_ref(<<1, rest::binary>>) do
    {proposal, rest} = Message.decode_proposal(rest)
    {{:proposal, proposal}, rest}
  end

  def decode_proposal_or_ref(<<2, rest::binary>>) do
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

  def decode_hpke_ciphertext(binary) do
    {kem_output, rest} = Codec.decode_vector(binary)
    {ciphertext, rest} = Codec.decode_vector(rest)
    {{kem_output, ciphertext}, rest}
  end
end
