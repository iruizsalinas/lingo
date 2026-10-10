defmodule Lingo.MLS.Group.Util do
  @moduledoc false

  # Small helpers shared by the group modules.

  alias Lingo.MLS.{Codec, Crypto, Tree, Welcome}

  def encode_context(context), do: encode(Welcome.encode_group_context(context))

  def encode(iodata), do: IO.iodata_to_binary(iodata)

  def interim_transcript_hash(confirmed, confirmation_tag),
    do: Crypto.hash([confirmed, Codec.vector(confirmation_tag)])

  # keeps only the private keys that still match a node in the tree
  def prune_keys(keys, tree) do
    Map.filter(keys, fn {x, {public_key, _private_key}} ->
      match?(%{encryption_key: ^public_key}, Tree.get(tree, x))
    end)
  end

  def equal?(a, b) when is_binary(a) and is_binary(b) and byte_size(a) == byte_size(b),
    do: :crypto.hash_equals(a, b)

  def equal?(_a, _b), do: false

  def check(true, _reason), do: :ok
  def check(false, reason), do: {:error, reason}

  def fetch(nil, reason), do: {:error, reason}
  def fetch(value, _reason), do: {:ok, value}

  def or_error(:error, reason), do: {:error, reason}
  def or_error(ok, _reason), do: ok
end
