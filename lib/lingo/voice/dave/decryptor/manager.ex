defmodule Lingo.Voice.Dave.Decryptor.Manager do
  @moduledoc false

  # One epoch's key ratchet (libdave's CryptorManager): generation keys made
  # on demand and expired after a while, and the nonces seen, to reject replays.

  import Bitwise

  alias Lingo.Voice.Dave.{Encryptor, Frame, KeyRatchet}

  @expiry 10_000
  @max_generation_gap 250
  @max_missing_nonces 1_000
  # 50 audio frames plus two 60 fps video streams, per second
  @max_frames_per_second 170

  def new_manager(ratchet, now) do
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

  def decrypt_with(manager, parsed, now) do
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

  def big_nonce(generation, nonce), do: generation <<< 24 ||| (nonce &&& 0xFFFFFF)

  def fresh_nonce?(manager, big_nonce) do
    expected = if manager.newest_nonce, do: manager.newest_nonce + 1, else: 0
    big_nonce >= expected or big_nonce in manager.missing_nonces
  end

  def key(manager, generation, now) do
    lifetime_seconds = div(now - manager.created_at, 1000)
    max_generation = (@max_frames_per_second * lifetime_seconds) >>> 24

    cond do
      generation < manager.oldest_generation -> :error
      generation > manager.newest_generation + @max_generation_gap -> :error
      generation > max_generation -> :error
      true -> fetch_key(manager, generation, now)
    end
  end

  def fetch_key(manager, generation, now) do
    with {:ok, key, ratchet} <- KeyRatchet.get(manager.ratchet, generation) do
      # keys for generations older than the newest one only live briefly
      expiry = if generation < manager.newest_generation, do: now + @expiry, else: :infinity
      generations = Map.put_new(manager.generations, generation, expiry)
      {:ok, key, %{manager | ratchet: ratchet, generations: generations}}
    end
  end

  def record_success(manager, generation, big_nonce, now) do
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
  def drop_expired_generations(manager, now) do
    generations = Map.reject(manager.generations, fn {_generation, expiry} -> expiry <= now end)
    advance_oldest(%{manager | generations: generations})
  end

  def advance_oldest(%{oldest_generation: oldest, newest_generation: newest} = manager)
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

  def advance_oldest(manager), do: manager
end
