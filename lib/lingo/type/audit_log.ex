defmodule Lingo.Type.AuditLog do
  @moduledoc """
  A guild's audit log, from `Lingo.Api.AuditLog.get/2`: its entries and the
  commands, rules, events, integrations, threads, users and webhooks they
  refer to. Integrations are partial.
  """

  alias Lingo.Type.{
    ApplicationCommand,
    AuditLogEntry,
    AutoModerationRule,
    Channel,
    Integration,
    Parse,
    ScheduledEvent,
    User,
    Webhook
  }

  @type t :: %__MODULE__{
          application_commands: [ApplicationCommand.t()],
          audit_log_entries: [AuditLogEntry.t()],
          auto_moderation_rules: [AutoModerationRule.t()],
          guild_scheduled_events: [ScheduledEvent.t()],
          integrations: [Integration.t()],
          threads: [Channel.t()],
          users: [User.t()],
          webhooks: [Webhook.t()]
        }

  defstruct application_commands: [],
            audit_log_entries: [],
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
      application_commands: Parse.list(data["application_commands"], &ApplicationCommand.new/1),
      audit_log_entries: Parse.list(data["audit_log_entries"], &AuditLogEntry.new/1),
      auto_moderation_rules: Parse.list(data["auto_moderation_rules"], &AutoModerationRule.new/1),
      guild_scheduled_events: Parse.list(data["guild_scheduled_events"], &ScheduledEvent.new/1),
      integrations: Parse.list(data["integrations"], &Integration.new/1),
      threads: Parse.list(data["threads"], &Channel.new/1),
      users: Parse.list(data["users"], &User.new/1),
      webhooks: Parse.list(data["webhooks"], &Webhook.new/1)
    }
  end
end
