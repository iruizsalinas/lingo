defmodule Lingo.Voice.RTPTest do
  use ExUnit.Case, async: true

  alias Lingo.Voice.{Opus, RTP}

  @key :binary.copy(<<9>>, 32)
  @header %{sequence: 513, timestamp: 0xDEADBEEF, ssrc: 77}

  describe "transport encryption" do
    for mode <- ["aead_aes256_gcm_rtpsize", "aead_xchacha20_poly1305_rtpsize"] do
      test "#{mode} round trips and authenticates the header" do
        packet = RTP.encrypt(unquote(mode), @key, @header, 41, "opus frame")

        assert <<0x80, 0x78, 513::16, 0xDEADBEEF::32, 77::32, _::binary>> = packet
        assert binary_part(packet, byte_size(packet), -4) == <<41::32>>
        assert {:ok, @header, "opus frame"} = RTP.decrypt(unquote(mode), @key, packet)

        <<first, second, _sequence::16, rest::binary>> = packet
        assert :error = RTP.decrypt(unquote(mode), @key, <<first, second, 514::16, rest::binary>>)
        assert :error = RTP.decrypt(unquote(mode), :binary.copy(<<1>>, 32), packet)
      end
    end

    test "the AES-GCM nonce is the counter followed by zeros" do
      packet = RTP.encrypt("aead_aes256_gcm_rtpsize", @key, @header, 7, "x")
      header = binary_part(packet, 0, 12)

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(:aes_256_gcm, @key, <<7::32, 0::64>>, "x", header, true)

      assert packet == header <> ciphertext <> tag <> <<7::32>>
    end

    test "strips an encrypted header extension and keeps CSRCs in the clear" do
      # X bit and one CSRC; the extension preamble says one 32 bit word follows
      header = <<0x91, 0x78, 1::16, 2::32, 3::32, 0xAAAA::32, 0xBEDE::16, 1::16>>
      plaintext = <<0x10, 0xFF, 0, 0>> <> "opus"

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(
          :aes_256_gcm,
          @key,
          <<5::32, 0::64>>,
          plaintext,
          header,
          true
        )

      packet = header <> ciphertext <> tag <> <<5::32>>
      assert {:ok, %{ssrc: 3}, "opus"} = RTP.decrypt("aead_aes256_gcm_rtpsize", @key, packet)
    end

    test "HChaCha20 matches draft-irtf-cfrg-xchacha" do
      key = :binary.list_to_bin(Enum.to_list(0..31))
      nonce = Base.decode16!("000000090000004A0000000031415927")

      assert Lingo.Voice.RTP.AEAD.hchacha20(key, nonce) ==
               Base.decode16!("82413B4227B27BFED30E42508A877D73A0F9E4D58A74A853C12EC41326D3ECDC")
    end

    test "rejects packets that are not voice" do
      assert :error = RTP.decrypt("aead_aes256_gcm_rtpsize", @key, <<0x80, 0xC9, 0::48>>)
      assert :error = RTP.decrypt("aead_aes256_gcm_rtpsize", @key, <<>>)
      refute RTP.voice_packet?(<<0x81, 0xC9, 0, 7>>)
      assert RTP.voice_packet?(RTP.encrypt("aead_aes256_gcm_rtpsize", @key, @header, 1, "x"))
    end
  end

  test "chooses the preferred mode" do
    assert RTP.choose_mode(["aead_xchacha20_poly1305_rtpsize", "aead_aes256_gcm_rtpsize"]) ==
             "aead_aes256_gcm_rtpsize"

    assert RTP.choose_mode(["aead_xchacha20_poly1305_rtpsize"]) ==
             "aead_xchacha20_poly1305_rtpsize"

    assert RTP.choose_mode(["xsalsa20_poly1305"]) == nil
  end

  test "IP discovery packets" do
    assert <<1::16, 70::16, 99::32, 0::512, 0::16>> = RTP.discovery_request(99)

    address = String.pad_trailing("203.0.113.9", 64, <<0>>)

    assert {:ok, "203.0.113.9", 50_000} =
             RTP.parse_discovery(<<2::16, 70::16, 99::32, address::binary, 50_000::16>>)

    assert :error = RTP.parse_discovery("short")
  end

  test "Opus packet durations from the TOC byte" do
    # CELT 20 ms, one frame
    assert Opus.samples(<<0xFC, 1, 2>>) == 960
    # CELT 10 ms, two frames
    assert Opus.samples(<<0xF1>>) == 960
    # SILK 60 ms, one frame
    assert Opus.samples(<<0x18>>) == 2880
    # CELT 2.5 ms, code 3 with 4 frames
    assert Opus.samples(<<0x83, 4>>) == 480
    assert Opus.samples(<<>>) == 960
  end
end
