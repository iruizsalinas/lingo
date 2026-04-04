defmodule Lingo.Type.AuditLog do
  @moduledoc false

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

defmodule Lingo.Type.AuditLogEntry do
  @moduledoc false

  @type t :: %__MODULE__{
          id: String.t(),
          target_id: String.t() | nil,
          changes: [map()],
          user_id: String.t() | nil,
          action_type: integer(),
          options: map() | nil,
          reason: String.t() | nil
        }

  defstruct [:id, :target_id, :user_id, :action_type, :options, :reason, changes: []]

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      target_id: data["target_id"],
      changes: data["changes"] || [],
      user_id: data["user_id"],
      action_type: data["action_type"],
      options: data["options"],
      reason: data["reason"]
    }
  end
end
