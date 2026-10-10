defmodule Lingo.Endpoint.Signature do
  @moduledoc false

  # Discord signs every request it sends to an app's endpoints with Ed25519:
  # X-Signature-Ed25519 holds the signature (hex) of the X-Signature-Timestamp
  # header followed by the raw body, checked against the app's public key
  # (hex, from the Developer Portal).

  @spec valid?(map(), binary(), String.t()) :: boolean()
  def valid?(headers, body, public_key) do
    with signature when is_binary(signature) <- headers["x-signature-ed25519"],
         timestamp when is_binary(timestamp) <- headers["x-signature-timestamp"],
         {:ok, <<_::binary-64>> = signature} <- Base.decode16(signature, case: :mixed),
         {:ok, <<_::binary-32>> = key} <- Base.decode16(public_key, case: :mixed) do
      :crypto.verify(:eddsa, :none, timestamp <> body, signature, [key, :ed25519])
    else
      _missing_or_malformed -> false
    end
  end

  @doc "Header names lowercased, values as strings, from a list or map of either."
  @spec headers(Enumerable.t()) :: map()
  def headers(headers),
    do:
      Map.new(headers, fn {name, value} ->
        {String.downcase(to_string(name)), to_string(value)}
      end)
end
