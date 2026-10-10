defmodule Lingo.Error do
  @moduledoc """
  A failed Discord API call.

  Every REST function returns `{:error, %Lingo.Error{}}` on failure, and the
  `!` helpers raise it. Match on `:reason` to tell failures apart:

    * `:api` - Discord rejected the request. `:status` is the HTTP status,
      `:code` Discord's [JSON error code](https://discord.com/developers/docs/topics/opcodes-and-status-codes#json),
      `:message` its explanation and `:errors` the per-field errors, if any.
    * `:rate_limited` - the request would have to wait longer than allowed
      (see `Lingo.with_max_wait/2`) or kept getting 429s. `:retry_after` is in ms.
    * `:server_error` - Discord kept answering 5xx; `:status` is the last one.
    * `:transport` - the request never got an answer; `:details` says why.
    * `:index_not_ready` - message search gave up waiting for Discord to index the guild.

  ```elixir
  case Lingo.Api.Message.get(channel_id, message_id) do
    {:ok, message} -> message
    {:error, %Lingo.Error{status: 404}} -> nil
  end
  ```
  """

  @type reason :: :api | :rate_limited | :server_error | :transport | :index_not_ready

  @type t :: %__MODULE__{
          reason: reason(),
          status: pos_integer() | nil,
          code: integer() | nil,
          message: String.t() | nil,
          errors: map() | nil,
          retry_after: non_neg_integer() | nil,
          details: term()
        }

  defexception [:reason, :status, :code, :message, :errors, :retry_after, :details]

  @doc false
  @spec from_response(pos_integer(), term()) :: t()
  def from_response(status, %{} = body) do
    %__MODULE__{
      reason: :api,
      status: status,
      code: body["code"],
      message: body["message"],
      errors: body["errors"],
      details: body
    }
  end

  def from_response(status, body), do: %__MODULE__{reason: :api, status: status, details: body}

  @impl true
  def message(%__MODULE__{reason: :api} = e) do
    code = if e.code, do: " (code #{e.code})", else: ""
    text = e.message || inspect(e.details)
    errors = if e.errors, do: "\n" <> inspect(e.errors, pretty: true), else: ""
    "Discord returned #{e.status}#{code}: #{text}#{errors}"
  end

  def message(%__MODULE__{reason: :rate_limited, retry_after: ms}),
    do: "rate limited, retry after #{ms}ms"

  def message(%__MODULE__{reason: :server_error, status: status}),
    do: "Discord kept failing with #{status}"

  def message(%__MODULE__{reason: :transport, details: details}),
    do: "request failed: #{inspect(details)}"

  def message(%__MODULE__{reason: :index_not_ready}),
    do: "the guild's messages aren't indexed yet"
end
