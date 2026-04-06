defmodule Lingo.Gateway.CompressionTest do
  use ExUnit.Case, async: true

  alias Lingo.Gateway.Compression

  # mimics how discord compresses gateway payloads
  defp gateway_compress(data) do
    z = :zlib.open()
    :zlib.deflateInit(z)
    compressed = :zlib.deflate(z, data, :sync)
    :zlib.close(z)
    IO.iodata_to_binary(compressed)
  end

  describe "new/0" do
    test "creates a compression context with empty buffer" do
      ctx = Compression.new()
      assert %Compression{} = ctx
      assert ctx.buffer == []
      Compression.close(ctx)
    end
  end

  describe "push/2" do
    test "decompresses a complete zlib-stream frame" do
      original = ~s({"op":10,"d":{"heartbeat_interval":45000}})
      compressed = gateway_compress(original)

      ctx = Compression.new()
      {ctx, result} = Compression.push(ctx, compressed)

      assert result != nil
      assert result == original

      decoded = Jason.decode!(result)
      assert decoded["op"] == 10
      assert decoded["d"]["heartbeat_interval"] == 45000

      Compression.close(ctx)
    end

    test "buffers partial data until Z_SYNC_FLUSH suffix arrives" do
      original = "hello world"
      compressed = gateway_compress(original)

      # split right before the 4-byte sync flush suffix
      split_at = byte_size(compressed) - 4
      <<part1::binary-size(^split_at), part2::binary>> = compressed

      ctx = Compression.new()

      # first chunk has no suffix, should buffer
      {ctx, result1} = Compression.push(ctx, part1)
      assert result1 == nil

      # second chunk completes it
      {ctx, result2} = Compression.push(ctx, part2)
      assert result2 == original

      Compression.close(ctx)
    end

    test "handles multiple sequential messages on a shared zlib context" do
      msg1 = ~s({"op":11})
      msg2 = ~s({"op":0,"t":"READY","d":{}})

      # discord reuses one deflate context for the whole connection
      z = :zlib.open()
      :zlib.deflateInit(z)
      compressed1 = IO.iodata_to_binary(:zlib.deflate(z, msg1, :sync))
      compressed2 = IO.iodata_to_binary(:zlib.deflate(z, msg2, :sync))
      :zlib.close(z)

      ctx = Compression.new()

      {ctx, result1} = Compression.push(ctx, compressed1)
      assert result1 == msg1

      {ctx, result2} = Compression.push(ctx, compressed2)
      assert result2 == msg2

      Compression.close(ctx)
    end
  end

  describe "close/1" do
    test "returns :ok on fresh context" do
      ctx = Compression.new()
      assert Compression.close(ctx) == :ok
    end

    test "returns :ok on used context" do
      ctx = Compression.new()
      compressed = gateway_compress("test")
      {ctx, _} = Compression.push(ctx, compressed)
      assert Compression.close(ctx) == :ok
    end
  end
end
