defmodule Lingo.Type.AuditLogEntry do
  @moduledoc """
  One audit log entry. Also the payload of `:guild_audit_log_entry_create` events.

  `action_type` is Discord's audit log event, lowercased (`:member_ban_add`,
  `:message_delete`, ...); types newer than Lingo stay integers.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          target_id: String.t() | nil,
          changes: [map()],
          guild_id: String.t() | nil,
          user_id: String.t() | nil,
          action_type: atom() | integer(),
          options: map() | nil,
          reason: String.t() | nil
        }

  defstruct [:id, :target_id, :guild_id, :user_id, :action_type, :options, :reason, changes: []]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      target_id: data["target_id"],
      guild_id: data["guild_id"],
      changes: data["changes"] || [],
      user_id: data["user_id"],
      action_type: Lingo.Type.Codes.name(:audit_log_event, data["action_type"]),
      options: data["options"],
      reason: data["reason"]
    }
  end
end
