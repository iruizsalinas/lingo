defmodule Lingo.ConfigTest do
  use ExUnit.Case, async: true

  alias Lingo.Config

  defp validate(opts), do: Config.validate!([bot: __MODULE__, token: "t"] ++ opts)

  test "gateway options default to JSON over zlib" do
    assert Enum.sort(validate([])[:gateway]) == [compression: :zlib, encoding: :json]
    assert validate(gateway: [encoding: :etf])[:gateway][:encoding] == :etf

    assert_raise ArgumentError, ~r/encoding/, fn -> validate(gateway: [encoding: :xml]) end
    assert_raise ArgumentError, ~r/compression/, fn -> validate(gateway: [compression: :gzip]) end
    assert_raise ArgumentError, fn -> validate(gateway: [unknown: true]) end
  end

  test "zstd needs OTP 28" do
    if Lingo.Gateway.Compression.zstd_available?() do
      assert validate(gateway: [compression: :zstd])[:gateway][:compression] == :zstd
    else
      assert_raise ArgumentError, ~r/OTP 28/, fn -> validate(gateway: [compression: :zstd]) end
    end
  end

  test "sharding options" do
    assert validate(sharding: [auto_reshard: true])[:sharding][:auto_reshard]
    assert validate(sharding: [auto_reshard: 60_000])[:sharding][:auto_reshard] == 60_000

    assert_raise ArgumentError, ~r/auto_reshard/, fn ->
      validate(sharding: [auto_reshard: :often])
    end

    assert_raise ArgumentError, fn -> validate(sharding: [shards: 2]) end
  end

  test "a session store is a module or {module, opts}" do
    store = Lingo.Gateway.SessionStore.File

    assert validate(sharding: [session_store: store])[:sharding][:session_store] == {store, []}

    assert validate(sharding: [session_store: {store, path: "s"}])[:sharding][:session_store] ==
             {store, path: "s"}

    assert_raise ArgumentError, ~r/SessionStore/, fn ->
      validate(sharding: [session_store: String])
    end
  end

  test "a REST base URL is an http(s) URL" do
    assert validate(rest: [base_url: "http://proxy/api/v10"])[:rest][:base_url]
    assert_raise ArgumentError, ~r/base_url/, fn -> validate(rest: [base_url: "proxy/"]) end
    assert_raise ArgumentError, ~r/base_url/, fn -> validate(rest: [base_url: "http://p/"]) end
  end

  test "endpoint options need the app's public key" do
    key = String.duplicate("ab", 32)

    assert validate(endpoint: [public_key: key, port: 4000])[:endpoint][:interactions_path] ==
             "/interactions"

    assert_raise ArgumentError, ~r/public_key/, fn -> validate(endpoint: [port: 4000]) end
    assert_raise ArgumentError, ~r/public_key/, fn -> validate(endpoint: [public_key: "abc"]) end

    assert_raise ArgumentError, ~r/port/, fn ->
      validate(endpoint: [public_key: key, port: -1])
    end

    assert validate(gateway: false)[:gateway] == false
  end
end
