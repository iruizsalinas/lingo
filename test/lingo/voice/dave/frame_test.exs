defmodule Lingo.Voice.Dave.FrameTest do
  use ExUnit.Case, async: true

  alias Lingo.MLS.Crypto
  alias Lingo.Voice.Dave.{Decryptor, Encryptor, Frame, KeyRatchet}

  @key :binary.copy(<<7>>, 16)

  describe "frames" do
    test "an encrypted Opus frame has the libdave layout" do
      frame = Frame.encrypt("opus data", @key, 1)

      # ciphertext, 8 byte tag, ULEB128 nonce, no ranges, size, marker
      assert byte_size(frame) == 9 + 8 + 1 + 1 + 2
      assert binary_part(frame, byte_size(frame), -3) == <<12, 0xFA, 0xFA>>

      {:ok, parsed} = Frame.parse(frame)
      assert parsed.nonce == 1
      assert {:ok, "opus data"} = Frame.decrypt(parsed, @key)
    end

    test "the nonce expands little-endian after eight zero bytes" do
      frame = Frame.encrypt("x", @key, 0x01020304)
      {:ok, parsed} = Frame.parse(frame)

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(:aes_128_gcm, @key, <<0::64, 4, 3, 2, 1>>, "x", "", 8, true)

      assert parsed.ciphertext == ciphertext and parsed.tag == tag
    end

    test "unencrypted ranges stay in the clear and are authenticated" do
      frame = Frame.encrypt("HEADERpayloadTAIL", @key, 5, [{0, 6}, {13, 4}])

      assert binary_part(frame, 0, 6) == "HEADER"
      assert binary_part(frame, 13, 4) == "TAIL"

      {:ok, parsed} = Frame.parse(frame)
      assert {:ok, "HEADERpayloadTAIL"} = Frame.decrypt(parsed, @key)

      tampered = "XEADER" <> binary_part(frame, 6, byte_size(frame) - 6)
      {:ok, parsed} = Frame.parse(tampered)
      assert :error = Frame.decrypt(parsed, @key)
    end

    test "rejects anything that is not a protocol frame" do
      assert :error = Frame.parse("plain opus")
      assert :error = Frame.parse(<<0::80, 3, 0xFA, 0xFA>>)
      # size larger than the frame
      assert :error = Frame.parse(<<0::80, 200, 0xFA, 0xFA>>)
      # ranges out of order
      frame = Frame.encrypt("abcdefgh", @key, 1)
      bad_ranges = binary_part(frame, 0, byte_size(frame) - 3) <> <<4, 1, 0, 1>>
      assert :error = Frame.parse(bad_ranges <> <<byte_size(bad_ranges) - 8 + 3, 0xFA, 0xFA>>)
    end

    test "ULEB128" do
      for value <- [0, 1, 127, 128, 300, 0xFFFFFFFF, 0xFFFFFFFFFFFFFFFF] do
        assert Frame.decode_uleb128(Frame.uleb128(value) <> "rest") == {:ok, value, "rest"}
      end

      assert Frame.uleb128(300) == <<0xAC, 0x02>>
      assert :error = Frame.decode_uleb128(<<0x80>>)
      assert :error = Frame.decode_uleb128(:binary.copy(<<0xFF>>, 11))
    end
  end

  describe "key ratchet" do
    test "derives generations deterministically and forgets erased ones" do
      ratchet = KeyRatchet.from_secret(:binary.copy(<<1>>, 16))
      {:ok, key3, ratchet} = KeyRatchet.get(ratchet, 3)
      {:ok, key1, ratchet} = KeyRatchet.get(ratchet, 1)

      expected =
        Enum.reduce(0..2, :binary.copy(<<1>>, 16), fn generation, secret ->
          Crypto.derive_tree_secret(secret, "secret", generation, 32)
        end)

      assert key3 == Crypto.derive_tree_secret(expected, "key", 3, 16)
      assert key1 != key3

      assert :error = ratchet |> KeyRatchet.erase(1) |> KeyRatchet.get(1)
    end
  end

  describe "encryptor and decryptor" do
    test "plaintext is rejected by default regardless of the monotonic clock origin" do
      for now <- [-120_000, 0, 120_000] do
        decryptor = Decryptor.new()
        assert {:error, :not_encrypted, _} = Decryptor.decrypt(decryptor, "plain", now)

        disabled = Decryptor.passthrough(decryptor, false, now, 100)
        assert {:error, :not_encrypted, _} = Decryptor.decrypt(disabled, "plain", now)

        enabled = Decryptor.passthrough(decryptor, true, now)
        expiring = Decryptor.passthrough(enabled, false, now, 100)
        assert {:ok, "plain", _} = Decryptor.decrypt(expiring, "plain", now + 99)
        assert {:error, :not_encrypted, _} = Decryptor.decrypt(expiring, "plain", now + 100)
      end
    end

    setup do
      ratchet = KeyRatchet.from_secret(:crypto.strong_rand_bytes(16))

      %{
        ratchet: ratchet,
        encryptor: Encryptor.new(ratchet),
        decryptor: Decryptor.add_ratchet(Decryptor.new(), ratchet, 0)
      }
    end

    test "round trips and rejects replays", %{encryptor: encryptor, decryptor: decryptor} do
      {:ok, first, encryptor} = Encryptor.encrypt(encryptor, "one")
      {:ok, second, _encryptor} = Encryptor.encrypt(encryptor, "two")

      {:ok, "two", decryptor} = Decryptor.decrypt(decryptor, second, 1)
      # an older frame that never arrived is still accepted, once
      {:ok, "one", decryptor} = Decryptor.decrypt(decryptor, first, 2)
      assert {:error, :decryption_failed, _} = Decryptor.decrypt(decryptor, first, 3)
      assert {:error, :decryption_failed, _} = Decryptor.decrypt(decryptor, second, 3)
    end

    test "passes silence through and only allows plaintext in passthrough", %{
      decryptor: decryptor
    } do
      assert {:ok, <<0xF8, 0xFF, 0xFE>>, _} = Decryptor.decrypt(decryptor, Frame.silence(), 0)
      assert {:error, :not_encrypted, _} = Decryptor.decrypt(decryptor, "plain", 0)

      decryptor = Decryptor.passthrough(decryptor, true, 0)
      assert {:ok, "plain", decryptor} = Decryptor.decrypt(decryptor, "plain", 0)

      decryptor = Decryptor.passthrough(decryptor, false, 0, 100)
      assert {:ok, "plain", _} = Decryptor.decrypt(decryptor, "plain", 99)
      assert {:error, :not_encrypted, _} = Decryptor.decrypt(decryptor, "plain", 100)
    end

    test "keeps the previous epoch's keys for ten seconds", %{
      encryptor: old,
      decryptor: decryptor
    } do
      new_ratchet = KeyRatchet.from_secret(:crypto.strong_rand_bytes(16))
      decryptor = Decryptor.add_ratchet(decryptor, new_ratchet, 1_000)

      {:ok, late_frame, _} = Encryptor.encrypt(old, "late")
      {:ok, new_frame, _} = Encryptor.encrypt(Encryptor.new(new_ratchet), "new")

      assert {:ok, "new", decryptor} = Decryptor.decrypt(decryptor, new_frame, 2_000)
      assert {:ok, "late", _} = Decryptor.decrypt(decryptor, late_frame, 10_999)
      assert {:error, :decryption_failed, _} = Decryptor.decrypt(decryptor, late_frame, 11_000)
    end

    test "adding the same ratchet twice changes nothing", %{
      ratchet: ratchet,
      decryptor: decryptor
    } do
      assert Decryptor.add_ratchet(decryptor, ratchet, 5_000) == decryptor
    end

    test "rejects frames for generations far in the future", %{
      ratchet: ratchet,
      decryptor: decryptor
    } do
      encryptor = %{Encryptor.new(ratchet) | nonce: 5 * 0x1000000}
      {:ok, frame, _} = Encryptor.encrypt(encryptor, "future")
      assert {:error, :decryption_failed, _} = Decryptor.decrypt(decryptor, frame, 0)
    end

    test "generations keep counting across a nonce wrap" do
      assert Encryptor.wrapped_generation(255, 0) == 256
      assert Encryptor.wrapped_generation(256, 1) == 257
      assert Encryptor.wrapped_generation(3, 5) == 5
    end
  end
end
