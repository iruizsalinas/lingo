defmodule Lingo.Test.MLSVectors do
  @moduledoc false

  # Loads the IETF MLS interop test vectors (github.com/mlswg/mls-implementations),
  # trimmed to ciphersuite 2, the only one DAVE uses.

  @dir Path.expand("../fixtures/mls", __DIR__)

  def load(name), do: Path.join(@dir, name <> ".json") |> File.read!() |> JSON.decode!()

  def hex(nil), do: nil
  def hex(string), do: Base.decode16!(string, case: :lower)
end
