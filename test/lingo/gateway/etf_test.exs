defmodule Lingo.Gateway.ETFTest do
  use ExUnit.Case, async: true

  alias Lingo.Gateway.{Codec, ETF}

  # Discord's ETF: atom keys, nil, snowflakes as integers
  defp etf(term, opts \\ []), do: :erlang.term_to_binary(term, opts)

  test "decodes payloads into what JSON would give" do
    payload = %{
      op: 0,
      t: :MESSAGE_CREATE,
      s: 12,
      d: %{
        id: 1_234_567_890_123_456_789,
        content: "héllo",
        mentions: [],
        mention_roles: [1_234_567_890_123_456_780],
        member: nil,
        tts: false,
        pinned: true,
        nonce: "abc",
        score: 1.5,
        flags: 4,
        delta: -3
      }
    }

    assert {:ok, decoded} = ETF.decode(etf(payload))

    assert decoded == %{
             "op" => 0,
             "t" => "MESSAGE_CREATE",
             "s" => 12,
             "d" => %{
               "id" => "1234567890123456789",
               "content" => "héllo",
               "mentions" => [],
               "mention_roles" => ["1234567890123456780"],
               "member" => nil,
               "tts" => false,
               "pinned" => true,
               "nonce" => "abc",
               "score" => 1.5,
               "flags" => 4,
               "delta" => -3
             }
           }
  end

  test "lists of small integers stay lists" do
    # term_to_binary writes these as STRING_EXT
    assert {:ok, %{"d" => [1, 2, 3]}} = ETF.decode(etf(%{d: [1, 2, 3]}))
  end

  test "activity timestamps stay numbers" do
    activity = %{
      timestamps: %{start: 1_700_000_000_000, end: 1_700_000_100_000},
      created_at: 1_700_000_000_000
    }

    assert {:ok,
            %{
              "timestamps" => %{"start" => 1_700_000_000_000, "end" => 1_700_000_100_000},
              "created_at" => 1_700_000_000_000
            }} = ETF.decode(etf(activity))
  end

  test "decodes compressed terms" do
    payload = %{d: String.duplicate("a", 1_000)}
    assert {:ok, %{"d" => d}} = ETF.decode(etf(payload, compressed: 9))
    assert d == String.duplicate("a", 1_000)
  end

  test "never creates atoms" do
    name = "lingo_etf_#{System.unique_integer([:positive])}"
    # a map with that atom as a key, written by hand so the test doesn't create it
    data = <<131, 116, 1::32, 119, byte_size(name), name::binary, 97, 1>>

    assert {:ok, %{^name => 1}} = ETF.decode(data)
    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
  end

  test "rejects malformed input" do
    assert ETF.decode(<<131, 116, 0, 0, 0, 5>>) == :error
    assert ETF.decode(<<131, 200>>) == :error
    assert ETF.decode("not etf") == :error
    assert ETF.decode(etf(%{a: 1}) <> "trailing") == :error
  end

  test "encodes what Discord reads" do
    payload = %{"op" => 2, "d" => %{"token" => "t", "shard" => [0, 1], "presence" => nil}}
    assert {:binary, data} = Codec.encode(payload, :etf)
    assert :erlang.binary_to_term(data) == payload
    assert {:ok, ^payload} = Codec.decode(data, :etf)
  end

  test "both encodings decode only maps" do
    assert {:text, json} = Codec.encode(%{"op" => 1}, :json)
    assert Codec.decode(json, :json) == {:ok, %{"op" => 1}}
    assert Codec.decode("[1]", :json) == :error
    assert Codec.decode(etf([1]), :etf) == :error
  end
end
