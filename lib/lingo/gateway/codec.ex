defmodule Lingo.Gateway.Codec do
  @moduledoc false

  # The gateway encodings: JSON in text frames, ETF in binary frames. Both
  # decode to the same maps, so nothing past the connection knows which one
  # is in use.

  alias Lingo.Gateway.ETF

  @type encoding :: :json | :etf
  @type frame :: {:text | :binary, iodata()}

  @spec encode(map(), encoding()) :: frame()
  def encode(payload, :json), do: {:text, JSON.encode!(payload)}
  def encode(payload, :etf), do: {:binary, ETF.encode(payload)}

  @spec decode(binary(), encoding()) :: {:ok, map()} | :error
  def decode(data, :json) do
    case JSON.decode(data) do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      _error -> :error
    end
  end

  def decode(data, :etf) do
    case ETF.decode(data) do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      _error -> :error
    end
  end
end
