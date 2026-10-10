defmodule Lingo.Api.AuditLog do
  @moduledoc """
  Guild audit logs.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.AuditLog

  @doc "Fetches a guild's audit log, optionally filtered by `user_id:`, `action_type:`, `before:` and `limit:`."
  @spec get(Api.id(), keyword()) :: Api.result(AuditLog.t())
  def get(guild_id, opts \\ []) do
    params =
      Client.params(opts)

    Client.request(:get, "/guilds/#{guild_id}/audit-logs", params: params)
    |> Client.into(&AuditLog.new/1)
  end
end
