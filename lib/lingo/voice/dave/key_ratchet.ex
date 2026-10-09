defmodule Lingo.Voice.Dave.KeyRatchet do
  @moduledoc false

  # The per-sender media key ratchet (DAVE protocol, "Sender Key Derivation"):
  # mlspp's HashRatchet, i.e. the RFC 9420 section 9.1 sender ratchet, seeded
  # each epoch with MLS-Exporter("Discord Secure Frames v0", sender id, 16).
  # The sender id is the user's snowflake as a little-endian uint64.

  alias Lingo.MLS.{Crypto, Group}

  @label "Discord Secure Frames v0"
  @key_size 16

  @enforce_keys [:base_secret, :secret]
  defstruct [:base_secret, :secret, next_generation: 0, keys: %{}]

  @type t :: %__MODULE__{}

  @spec new(Group.t(), non_neg_integer()) :: t()
  def new(group, user_id),
    do: from_secret(Group.export(group, @label, <<user_id::64-little>>, @key_size))

  @spec from_secret(binary()) :: t()
  def from_secret(base_secret), do: %__MODULE__{base_secret: base_secret, secret: base_secret}

  @doc "The key for a generation, ratcheting forward as needed. Erased generations are gone."
  @spec get(t(), non_neg_integer()) :: {:ok, binary(), t()} | :error
  def get(ratchet, generation) do
    cond do
      Map.has_key?(ratchet.keys, generation) -> {:ok, ratchet.keys[generation], ratchet}
      generation < ratchet.next_generation -> :error
      true -> get(advance(ratchet), generation)
    end
  end

  @spec erase(t(), non_neg_integer()) :: t()
  def erase(ratchet, generation), do: %{ratchet | keys: Map.delete(ratchet.keys, generation)}

  defp advance(%{next_generation: generation, secret: secret} = ratchet) do
    key = Crypto.derive_tree_secret(secret, "key", generation, @key_size)
    next_secret = Crypto.derive_tree_secret(secret, "secret", generation, Crypto.hash_size())

    %{
      ratchet
      | secret: next_secret,
        next_generation: generation + 1,
        keys: Map.put(ratchet.keys, generation, key)
    }
  end
end
