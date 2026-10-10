defmodule Lingo.Event.RateLimited do
  @moduledoc """
  The payload of `:rate_limited`: Discord refused a gateway request, such as
  `Lingo.Gateway.request_guild_members/2`, for `retry_after` ms.

  For member requests, `guild_id` and `nonce` name the request. Rate limits
  on API calls are not events; see `Lingo.Telemetry`.
  """

  @type t :: %__MODULE__{
          opcode: :request_guild_members | integer(),
          retry_after: non_neg_integer(),
          guild_id: String.t() | nil,
          nonce: String.t() | nil
        }

  defstruct [:opcode, :guild_id, :nonce, retry_after: 0]

  @opcodes %{8 => :request_guild_members}

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    meta = data["meta"] || %{}

    %__MODULE__{
      opcode: Map.get(@opcodes, data["opcode"], data["opcode"]),
      retry_after: ceil((data["retry_after"] || 0) * 1000),
      guild_id: meta["guild_id"],
      nonce: meta["nonce"]
    }
  end
end
