defmodule Lingo.Api.AuditLog do
  @moduledoc """
  Guild audit logs.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.{AuditLog, Codes}

  @doc """
  Fetches a guild's audit log, optionally filtered by `user_id:`,
  `action_type:` (an atom like `:member_ban_add`, see
  `Lingo.Type.AuditLogEntry`), `before:`, `after:` and `limit:`.
  """
  @spec get(Api.id(), keyword()) :: Api.result(AuditLog.t())
  def get(guild_id, opts \\ []) do
    opts =
      if opts[:action_type],
        do: Keyword.update!(opts, :action_type, &Codes.code(:audit_log_event, &1)),
        else: opts

    params = Client.params(opts)

    Client.request(:get, "/guilds/#{guild_id}/audit-logs", params: params)
    |> Client.into(&AuditLog.new/1)
  end
end
