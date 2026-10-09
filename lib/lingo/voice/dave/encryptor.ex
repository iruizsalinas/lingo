defmodule Lingo.Voice.Dave.Encryptor do
  @moduledoc false

  # Encrypts our outgoing media frames. The 32 bit nonce counts frames within
  # an epoch; its top byte selects the ratchet generation, and generations keep
  # counting when the nonce wraps (libdave's Encryptor).

  import Bitwise

  alias Lingo.Voice.Dave.{Frame, KeyRatchet}

  @enforce_keys [:ratchet]
  defstruct [:ratchet, :key, nonce: 0, generation: 0]

  @type t :: %__MODULE__{}

  @spec new(KeyRatchet.t()) :: t()
  def new(ratchet), do: %__MODULE__{ratchet: ratchet}

  @spec encrypt(t(), binary()) :: {:ok, binary(), t()} | :error
  def encrypt(encryptor, frame) do
    nonce = encryptor.nonce + 1 &&& 0xFFFFFFFF
    generation = wrapped_generation(encryptor.generation, nonce >>> 24)

    with {:ok, key, encryptor} <- key(encryptor, generation) do
      {:ok, Frame.encrypt(frame, key, nonce), %{encryptor | nonce: nonce}}
    end
  end

  defp key(%{generation: generation, key: key} = encryptor, generation) when key != nil,
    do: {:ok, key, encryptor}

  defp key(encryptor, generation) do
    case KeyRatchet.get(encryptor.ratchet, generation) do
      {:ok, key, ratchet} ->
        ratchet = KeyRatchet.erase(ratchet, encryptor.generation)
        {:ok, key, %{encryptor | ratchet: ratchet, generation: generation, key: key}}

      :error ->
        :error
    end
  end

  @doc "Unwraps an 8 bit generation relative to the oldest one still in use."
  @spec wrapped_generation(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def wrapped_generation(oldest, generation) do
    remainder = rem(oldest, 256)
    factor = div(oldest, 256) + if(generation < remainder, do: 1, else: 0)
    factor * 256 + generation
  end
end
