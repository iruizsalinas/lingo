defmodule Lingo.Type.AutoModerationRule do
  @moduledoc "An auto moderation rule."

  @type event_type :: :message_send | :member_update
  @type trigger_type :: :keyword | :spam | :keyword_preset | :mention_spam | :member_profile

  @type action_type :: :block_message | :send_alert_message | :timeout | :block_member_interaction

  @type t :: %__MODULE__{
          id: String.t(),
          guild_id: String.t(),
          name: String.t(),
          creator_id: String.t(),
          event_type: event_type(),
          trigger_type: trigger_type(),
          trigger_metadata: map(),
          actions: [action()],
          enabled: boolean(),
          exempt_roles: [String.t()],
          exempt_channels: [String.t()]
        }

  @type action :: %{
          type: action_type(),
          metadata: map() | nil
        }

  defstruct [
    :id,
    :guild_id,
    :name,
    :creator_id,
    :event_type,
    :trigger_type,
    trigger_metadata: %{},
    actions: [],
    enabled: false,
    exempt_roles: [],
    exempt_channels: []
  ]

  @event_types %{1 => :message_send, 2 => :member_update}
  @trigger_types %{
    1 => :keyword,
    3 => :spam,
    4 => :keyword_preset,
    5 => :mention_spam,
    6 => :member_profile
  }
  @action_types %{
    1 => :block_message,
    2 => :send_alert_message,
    3 => :timeout,
    4 => :block_member_interaction
  }

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      guild_id: data["guild_id"],
      name: data["name"],
      creator_id: data["creator_id"],
      event_type: Map.get(@event_types, data["event_type"], data["event_type"]),
      trigger_type: trigger_type(data["trigger_type"]),
      trigger_metadata: data["trigger_metadata"] || %{},
      actions: (data["actions"] || []) |> Enum.map(&action/1),
      enabled: data["enabled"] || false,
      exempt_roles: data["exempt_roles"] || [],
      exempt_channels: data["exempt_channels"] || []
    }
  end

  @doc false
  def trigger_type(code), do: Map.get(@trigger_types, code, code)

  @doc false
  def action(%{"type" => type} = action) do
    %{
      type: Map.get(@action_types, type, type),
      metadata: action["metadata"]
    }
  end

  def action(action), do: action
end
