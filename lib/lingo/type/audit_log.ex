defmodule Lingo.Type.AuditLog do
  @moduledoc "A guild's audit log, from `Lingo.Api.AuditLog.get/2`."

  @type t :: %__MODULE__{
          audit_log_entries: [Lingo.Type.AuditLogEntry.t()],
          auto_moderation_rules: [map()],
          guild_scheduled_events: [map()],
          integrations: [map()],
          threads: [map()],
          users: [Lingo.Type.User.t()],
          webhooks: [map()]
        }

  defstruct audit_log_entries: [],
            auto_moderation_rules: [],
            guild_scheduled_events: [],
            integrations: [],
            threads: [],
            users: [],
            webhooks: []

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      audit_log_entries:
        (data["audit_log_entries"] || []) |> Enum.map(&Lingo.Type.AuditLogEntry.new/1),
      auto_moderation_rules: data["auto_moderation_rules"] || [],
      guild_scheduled_events: data["guild_scheduled_events"] || [],
      integrations: data["integrations"] || [],
      threads: data["threads"] || [],
      users: (data["users"] || []) |> Enum.map(&Lingo.Type.User.new/1),
      webhooks: data["webhooks"] || []
    }
  end
end
