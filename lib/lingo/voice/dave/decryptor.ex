defmodule Lingo.Voice.Dave.Decryptor do
  @moduledoc false

  # Decrypts one remote sender's media frames (libdave's Decryptor and
  # CryptorManager). There is one key ratchet per epoch; older ones stay usable
  # for 10 seconds after a newer one arrives, so frames in flight across a
  # transition still decrypt. Each ratchet tracks the nonces it has seen to
  # reject replays.
  #
  # Times are monotonic milliseconds, passed in so the logic stays pure.

  import Bitwise

  alias Lingo.Voice.Dave.{Encryptor, Frame, KeyRatchet}

  @expiry 10_000
  @max_generation_gap 250
  @max_missing_nonces 1_000
  # 50 audio frames plus two 60 fps video streams, per second
  @max_frames_per_second 170

  defstruct managers: [], passthrough_until: 0

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
      %{decryptor | managers: managers ++ [new_manager(ratchet, now)]}
    end
  end

  @doc "Allows unencrypted frames forever, or only for `expiry` more ms."
  @spec passthrough(t(), boolean(), integer(), non_neg_integer()) :: t()
  def passthrough(decryptor, allow?, now, expiry \\ @expiry)
  def passthrough(decryptor, true, _now, _expiry), do: %{decryptor | passthrough_until: :infinity}

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
          {:ok, parsed} -> decrypt_parsed(decryptor, parsed, now)
          :error when decryptor.passthrough_until > now -> {:ok, frame, decryptor}
          :error -> {:error, :not_encrypted, decryptor}
        end
    end
  end

  # newest ratchet first
  defp decrypt_parsed(decryptor, parsed, now) do
    decryptor.managers
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value({:error, :decryption_failed, decryptor}, fn {manager, index} ->
      case decrypt_with(manager, parsed, now) do
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

  defp new_manager(ratchet, now) do
    %{
      ratchet: ratchet,
      created_at: now,
      expiry: :infinity,
      oldest_generation: 0,
      newest_generation: 0,
      # generation => expiry of its key
      generations: %{},
      newest_nonce: nil,
      missing_nonces: []
    }
  end

  defp decrypt_with(manager, parsed, now) do
    manager = drop_expired_generations(manager, now)
    generation = Encryptor.wrapped_generation(manager.oldest_generation, parsed.nonce >>> 24)
    big_nonce = big_nonce(generation, parsed.nonce)

    with true <- fresh_nonce?(manager, big_nonce),
         {:ok, key, manager} <- key(manager, generation, now),
         {:ok, plaintext} <- Frame.decrypt(parsed, key) do
      {:ok, plaintext, record_success(manager, generation, big_nonce, now)}
    else
      _failure -> :error
    end
  end

  defp big_nonce(generation, nonce), do: generation <<< 24 ||| (nonce &&& 0xFFFFFF)

  defp fresh_nonce?(manager, big_nonce) do
    expected = if manager.newest_nonce, do: manager.newest_nonce + 1, else: 0
    big_nonce >= expected or big_nonce in manager.missing_nonces
  end

  defp key(manager, generation, now) do
    lifetime_seconds = div(now - manager.created_at, 1000)
    max_generation = (@max_frames_per_second * lifetime_seconds) >>> 24

    cond do
      generation < manager.oldest_generation -> :error
      generation > manager.newest_generation + @max_generation_gap -> :error
      generation > max_generation -> :error
      true -> fetch_key(manager, generation, now)
    end
  end

  defp fetch_key(manager, generation, now) do
    with {:ok, key, ratchet} <- KeyRatchet.get(manager.ratchet, generation) do
      # keys for generations older than the newest one only live briefly
      expiry = if generation < manager.newest_generation, do: now + @expiry, else: :infinity
      generations = Map.put_new(manager.generations, generation, expiry)
      {:ok, key, %{manager | ratchet: ratchet, generations: generations}}
    end
  end

  defp record_success(manager, generation, big_nonce, now) do
    expected = if manager.newest_nonce, do: manager.newest_nonce + 1, else: 0

    manager =
      if big_nonce >= expected do
        gap = min(big_nonce - expected, @max_missing_nonces)
        missing = Enum.to_list((big_nonce - gap)..(big_nonce - 1)//1)
        missing_nonces = Enum.take(manager.missing_nonces ++ missing, -@max_missing_nonces)
        %{manager | newest_nonce: big_nonce, missing_nonces: missing_nonces}
      else
        %{manager | missing_nonces: List.delete(manager.missing_nonces, big_nonce)}
      end

    if generation > manager.newest_generation do
      generations =
        Map.new(manager.generations, fn
          {older, expiry} when older < generation -> {older, min(expiry, now + @expiry)}
          entry -> entry
        end)

      %{manager | newest_generation: generation, generations: generations}
    else
      manager
    end
  end

  # forgets expired generation keys, oldest first, so they can never be used again
  defp drop_expired_generations(manager, now) do
    generations = Map.reject(manager.generations, fn {_generation, expiry} -> expiry <= now end)
    advance_oldest(%{manager | generations: generations})
  end

  defp advance_oldest(%{oldest_generation: oldest, newest_generation: newest} = manager)
       when oldest < newest do
    if Map.has_key?(manager.generations, oldest) do
      manager
    else
      advance_oldest(%{
        manager
        | oldest_generation: oldest + 1,
          ratchet: KeyRatchet.erase(manager.ratchet, oldest)
      })
    end
  end

  defp advance_oldest(manager), do: manager
end
