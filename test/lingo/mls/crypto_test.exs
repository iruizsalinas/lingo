defmodule Lingo.MLS.CryptoTest do
  use ExUnit.Case, async: true

  import Lingo.Test.MLSVectors

  alias Lingo.MLS.{Codec, Crypto, HPKE, TreeMath}

  describe "codec" do
    test "decodes variable-length size prefixes" do
      for %{"vlbytes_header" => header, "length" => length} <- load("deserialization") do
        header = hex(header)
        assert Codec.decode_varint(header) == {length, <<>>}
        assert Codec.varint(length) == header
      end
    end

    test "rejects non-minimal and reserved prefixes" do
      assert_raise ArgumentError, fn -> Codec.decode_varint(<<0x40, 0x05>>) end
      assert_raise ArgumentError, fn -> Codec.decode_varint(<<0x80, 0, 0, 0x05>>) end
      assert_raise ArgumentError, fn -> Codec.decode_varint(<<0xC0, 0, 0, 0, 0, 0, 0, 1>>) end
    end

    test "rejects truncated vectors and trailing bytes" do
      assert_raise ArgumentError, fn -> Codec.decode_vector(<<5, "abc">>) end

      assert_raise ArgumentError, fn ->
        Codec.decode_exact(<<1, "a", "b">>, &Codec.decode_vector/1)
      end
    end
  end

  test "tree math" do
    for vector <- load("tree-math") do
      n = vector["n_leaves"]
      assert TreeMath.node_width(n) == vector["n_nodes"]
      assert TreeMath.root(n) == vector["root"]

      for x <- 0..(vector["n_nodes"] - 1) do
        assert safe(fn -> TreeMath.left(x) end) == Enum.at(vector["left"], x)
        assert safe(fn -> TreeMath.right(x) end) == Enum.at(vector["right"], x)
        assert safe(fn -> TreeMath.parent(x, n) end) == Enum.at(vector["parent"], x)
        assert safe(fn -> TreeMath.sibling(x, n) end) == Enum.at(vector["sibling"], x)
      end
    end
  end

  test "common ancestors" do
    assert TreeMath.common_ancestor(0, 2) == 1
    assert TreeMath.common_ancestor(0, 6) == 3
    assert TreeMath.common_ancestor(8, 14) == 11
    assert TreeMath.common_ancestor(1, 0) == 1
  end

  defp safe(fun) do
    fun.()
  rescue
    ArgumentError -> nil
  end

  describe "crypto basics" do
    setup do
      [vector] = load("crypto-basics")
      %{vector: vector}
    end

    test "ref_hash", %{vector: %{"ref_hash" => v}} do
      assert Crypto.ref_hash(v["label"], hex(v["value"])) == hex(v["out"])
    end

    test "expand_with_label", %{vector: %{"expand_with_label" => v}} do
      assert Crypto.expand_with_label(
               hex(v["secret"]),
               v["label"],
               hex(v["context"]),
               v["length"]
             ) ==
               hex(v["out"])
    end

    test "derive_secret", %{vector: %{"derive_secret" => v}} do
      assert Crypto.derive_secret(hex(v["secret"]), v["label"]) == hex(v["out"])
    end

    test "derive_tree_secret", %{vector: %{"derive_tree_secret" => v}} do
      assert Crypto.derive_tree_secret(hex(v["secret"]), v["label"], v["generation"], v["length"]) ==
               hex(v["out"])
    end

    test "sign_with_label", %{vector: %{"sign_with_label" => v}} do
      assert Crypto.verify_with_label(
               hex(v["pub"]),
               v["label"],
               hex(v["content"]),
               hex(v["signature"])
             )

      signature = Crypto.sign_with_label(hex(v["priv"]), v["label"], hex(v["content"]))
      assert Crypto.verify_with_label(hex(v["pub"]), v["label"], hex(v["content"]), signature)
      refute Crypto.verify_with_label(hex(v["pub"]), v["label"], "other", signature)
    end

    test "encrypt_with_label", %{vector: %{"encrypt_with_label" => v}} do
      assert {:ok, plaintext} =
               Crypto.decrypt_with_label(
                 hex(v["priv"]),
                 v["label"],
                 hex(v["context"]),
                 hex(v["kem_output"]),
                 hex(v["ciphertext"])
               )

      assert plaintext == hex(v["plaintext"])

      {kem_output, ciphertext} =
        Crypto.encrypt_with_label(hex(v["pub"]), v["label"], hex(v["context"]), plaintext)

      assert {:ok, ^plaintext} =
               Crypto.decrypt_with_label(
                 hex(v["priv"]),
                 v["label"],
                 hex(v["context"]),
                 kem_output,
                 ciphertext
               )

      assert :error =
               Crypto.decrypt_with_label(
                 hex(v["priv"]),
                 "Other",
                 hex(v["context"]),
                 kem_output,
                 ciphertext
               )
    end
  end

  describe "hpke" do
    test "derived and generated key pairs are consistent" do
      {public_key, private_key} = HPKE.derive_key_pair(:binary.copy(<<7>>, 32))
      assert HPKE.public_key(private_key) == public_key
      assert HPKE.derive_key_pair(:binary.copy(<<7>>, 32)) == {public_key, private_key}

      {public_key, private_key} = HPKE.generate_key_pair()
      assert byte_size(private_key) == 32 and byte_size(public_key) == 65
    end

    test "rejects an invalid peer point" do
      {_public_key, private_key} = HPKE.generate_key_pair()
      assert HPKE.open(private_key, <<4, 0::512>>, "", "", :binary.copy(<<0>>, 32)) == :error
    end
  end
end
