defmodule Lingo.Type.AccessToken do
  @moduledoc """
  An OAuth2 token, from `Lingo.OAuth2`. `expires_at` is when it stops
  working, counted from when Discord answered; refresh it with
  `Lingo.OAuth2.refresh/2` before then. The client credentials grant gives
  no `refresh_token`.
  """

  @type t :: %__MODULE__{
          access_token: String.t(),
          token_type: String.t(),
          refresh_token: String.t() | nil,
          scopes: [String.t()],
          expires_at: DateTime.t() | nil
        }

  defstruct [:access_token, :token_type, :refresh_token, :expires_at, scopes: []]

  @doc false
  @spec new(map() | nil, DateTime.t()) :: t() | nil
  def new(data, now \\ DateTime.utc_now())
  def new(nil, _now), do: nil

  def new(data, now) when is_map(data) do
    %__MODULE__{
      access_token: data["access_token"],
      token_type: data["token_type"],
      refresh_token: data["refresh_token"],
      scopes: String.split(data["scope"] || "", " ", trim: true),
      expires_at: expires_at(data["expires_in"], now)
    }
  end

  @doc "Whether the token has expired, or will within `margin_ms`."
  @spec expired?(t(), non_neg_integer()) :: boolean()
  def expired?(token, margin_ms \\ 0)
  def expired?(%__MODULE__{expires_at: nil}, _margin_ms), do: false

  def expired?(%__MODULE__{expires_at: expires_at}, margin_ms) do
    soon = DateTime.add(DateTime.utc_now(), margin_ms, :millisecond)
    DateTime.compare(soon, expires_at) != :lt
  end

  defp expires_at(seconds, now) when is_integer(seconds), do: DateTime.add(now, seconds, :second)
  defp expires_at(_seconds, _now), do: nil
end
