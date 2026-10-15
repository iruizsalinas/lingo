defmodule Lingo.Voice.Dave.Decryptor do
  @moduledoc false

  # Decrypts one remote sender's media frames (libdave's Decryptor and
  # CryptorManager). There is one key ratchet per epoch; older ones stay usable
  # for 10 seconds after a newer one arrives, so frames in flight across a
  # transition still decrypt. Each ratchet tracks the nonces it has seen to
  # reject replays.
  #
  # Times are monotonic milliseconds, passed in so the logic stays pure.

  alias Lingo.Voice.Dave.Decryptor.Manager

  alias Lingo.Voice.Dave.{Frame, KeyRatchet}

  @expiry 10_000

  defstruct managers: [], passthrough_until: nil

  @type t :: %__MODULE__{}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Adds the ratchet for a new epoch; the older ones expire after `expiry` ms."
  @spec add_ratchet(t(), KeyRatchet.t(), integer(), non_neg_integer()) :: t()
  def add_ratchet(decryptor, ratchet, now, expiry \\ @expiry) do
    decryptor = drop_expired(decryptor, now)

    # a ratchet we already have is not a transition and must not reset anything
    if Enum.any?(decryptor.managers, &(&1.ratchet.base_secret == ratchet.base_secret)) do
      decryptor
    else
      managers = Enum.map(decryptor.managers, &%{&1 | expiry: min(&1.expiry, now + expiry)})
      %{decryptor | managers: managers ++ [Manager.new_manager(ratchet, now)]}
    end
  end

  @doc "Allows unencrypted frames forever, or only for `expiry` more ms."
  @spec passthrough(t(), boolean(), integer(), non_neg_integer()) :: t()
  def passthrough(decryptor, allow?, now, expiry \\ @expiry)
  def passthrough(decryptor, true, _now, _expiry), do: %{decryptor | passthrough_until: :infinity}

  def passthrough(%{passthrough_until: nil} = decryptor, false, _now, _expiry), do: decryptor

  def passthrough(decryptor, false, now, expiry),
    do: %{decryptor | passthrough_until: min(decryptor.passthrough_until, now + expiry)}

  @spec decrypt(t(), binary(), integer()) :: {:ok, binary(), t()} | {:error, atom(), t()}
  def decrypt(decryptor, frame, now) do
    decryptor = drop_expired(decryptor, now)

    cond do
      # the SFU may inject silence, which is never encrypted
      frame == Frame.silence() ->
        {:ok, frame, decryptor}

      true ->
        case Frame.parse(frame) do
          {:ok, parsed} ->
            decrypt_parsed(decryptor, parsed, now)

          :error
          when decryptor.passthrough_until == :infinity or
                 (is_integer(decryptor.passthrough_until) and decryptor.passthrough_until > now) ->
            {:ok, frame, decryptor}

          :error ->
            {:error, :not_encrypted, decryptor}
        end
    end
  end

  # newest ratchet first
  defp decrypt_parsed(decryptor, parsed, now) do
    decryptor.managers
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value({:error, :decryption_failed, decryptor}, fn {manager, index} ->
      case Manager.decrypt_with(manager, parsed, now) do
        {:ok, plaintext, manager} ->
          {:ok, plaintext,
           %{decryptor | managers: List.replace_at(decryptor.managers, index, manager)}}

        :error ->
          nil
      end
    end)
  end

  defp drop_expired(decryptor, now),
    do: %{decryptor | managers: Enum.reject(decryptor.managers, &(&1.expiry <= now))}

  ## One ratchet (libdave's CryptorManager)
end
