defmodule Lingo.Event.AutoModerationAction do
  @moduledoc """
  The payload of `:auto_moderation_action_execution`: an auto moderation
  rule acted on a message or member.

  `message_id` is `nil` when the message was blocked, and
  `alert_system_message_id` is set only for alert actions. `content` and
  `matched_content` need the message content intent.
  """

  alias Lingo.Type.AutoModerationRule

  @type t :: %__MODULE__{
          guild_id: String.t(),
          action: AutoModerationRule.action(),
          rule_id: String.t(),
          rule_trigger_type: AutoModerationRule.trigger_type() | integer(),
          user_id: String.t(),
          channel_id: String.t() | nil,
          message_id: String.t() | nil,
          alert_system_message_id: String.t() | nil,
          content: String.t(),
          matched_keyword: String.t() | nil,
          matched_content: String.t() | nil
        }

  defstruct [
    :guild_id,
    :action,
    :rule_id,
    :rule_trigger_type,
    :user_id,
    :channel_id,
    :message_id,
    :alert_system_message_id,
    :matched_keyword,
    :matched_content,
    content: ""
  ]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    struct(Lingo.Type.Parse.fields(__MODULE__, data),
      action: AutoModerationRule.action(data["action"]),
      rule_trigger_type: AutoModerationRule.trigger_type(data["rule_trigger_type"])
    )
  end
end
