defmodule Lingo.Gateway.WebSocket.FrameTest do
  use ExUnit.Case, async: true

  alias Lingo.Gateway.WebSocket.Frame

  @key <<1, 2, 3, 4>>

  defp encode(opcode, payload, opts \\ []),
    do: opcode |> Frame.encode(payload, opts) |> IO.iodata_to_binary()

  describe "encode/3" do
    test "uses the shortest length encoding" do
      assert <<0x81, 5, "hello">> = encode(:text, "hello")
      assert <<0x82, 126, 126::16, _::binary-126>> = encode(:binary, :binary.copy("a", 126))
      assert <<0x82, 127, 65_536::64, _::binary>> = encode(:binary, :binary.copy("a", 65_536))
    end

    test "masks the payload with the given key" do
      assert <<0x81, 0x85, @key, masked::binary-5>> = encode(:text, "hello", mask: @key)
      assert masked == :crypto.exor("hello", <<1, 2, 3, 4, 1>>)
    end

    test "clears FIN for non-final fragments" do
      assert <<0x01, 2, "he">> = encode(:text, "he", fin: false)
      assert <<0x80, 3, "llo">> = encode(:continuation, "llo")
    end

    test "accepts iodata" do
      assert encode(:text, ["he", ["l" | "lo"]]) == encode(:text, "hello")
    end
  end

  describe "decode/2" do
    test "round trips every length encoding, masked and unmasked" do
      for size <- [0, 1, 125, 126, 65_535, 65_536], masked? <- [true, false] do
        payload = :crypto.strong_rand_bytes(size)
        opts = if masked?, do: [mask: @key], else: []

        assert {:ok, {:binary, true, ^payload}, "rest"} =
                 Frame.decode(encode(:binary, payload, opts) <> "rest", masked: masked?)
      end
    end

    test "asks for more data until a whole frame has arrived" do
      frame = encode(:text, :binary.copy("a", 300), mask: @key)

      for size <- 0..(byte_size(frame) - 1) do
        assert Frame.decode(binary_part(frame, 0, size), masked: true) == :more
      end

      assert {:ok, {:text, true, _}, ""} = Frame.decode(frame, masked: true)
    end

    test "rejects frames masked the wrong way" do
      assert {:error, :unexpected_mask} = Frame.decode(encode(:text, "hi", mask: @key))
      assert {:error, :unexpected_mask} = Frame.decode(encode(:text, "hi"), masked: true)
    end

    test "rejects reserved bits and unknown opcodes" do
      assert {:error, :reserved_bits_set} = Frame.decode(<<0xC1, 0>>)
      assert {:error, :unknown_opcode} = Frame.decode(<<0x83, 0>>)
      assert {:error, :unknown_opcode} = Frame.decode(<<0x8B, 0>>)
    end

    test "rejects fragmented or oversized control frames" do
      assert {:error, :fragmented_control_frame} = Frame.decode(encode(:ping, "", fin: false))
      assert {:error, :control_frame_too_large} = Frame.decode(<<0x89, 126, 126::16>>)
    end

    test "rejects a 64 bit length with the most significant bit set" do
      assert {:error, :invalid_length} = Frame.decode(<<0x82, 127, 1::1, 0::63>>)
    end

    test "rejects frames over max_size from the header alone" do
      header = <<0x82, 127, 1_000_000::64>>
      assert {:error, :frame_too_large} = Frame.decode(header, max_size: 999_999)
      assert :more = Frame.decode(header, max_size: 1_000_000)
    end
  end
end
