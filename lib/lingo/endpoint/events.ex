defmodule Lingo.Endpoint.Events do
  @moduledoc false

  # Webhook events: names and payloads, as handle_event/2 receives them.

  alias Lingo.Type.{Entitlement, Guild, Message, User}

  @names %{
    "APPLICATION_AUTHORIZED" => :application_authorized,
    "APPLICATION_DEAUTHORIZED" => :application_deauthorized,
    "ENTITLEMENT_CREATE" => :entitlement_create,
    "ENTITLEMENT_UPDATE" => :entitlement_update,
    "ENTITLEMENT_DELETE" => :entitlement_delete,
    "QUEST_USER_ENROLLMENT" => :quest_user_enrollment,
    "LOBBY_MESSAGE_CREATE" => :lobby_message_create,
    "LOBBY_MESSAGE_UPDATE" => :lobby_message_update,
    "LOBBY_MESSAGE_DELETE" => :lobby_message_delete,
    "GAME_DIRECT_MESSAGE_CREATE" => :game_direct_message_create,
    "GAME_DIRECT_MESSAGE_UPDATE" => :game_direct_message_update,
    "GAME_DIRECT_MESSAGE_DELETE" => :game_direct_message_delete
  }

  @spec name(String.t()) :: atom() | {:unknown_event, String.t()}
  def name(type), do: Map.get(@names, type, {:unknown_event, type})

  @spec payload(atom() | tuple(), map() | nil) :: term()
  def payload(:application_authorized, data) do
    %{
      integration_type: integration_type(data["integration_type"]),
      user: User.new(data["user"]),
      scopes: data["scopes"] || [],
      guild: Guild.new(data["guild"])
    }
  end

  def payload(:application_deauthorized, data), do: %{user: User.new(data["user"])}

  def payload(event, data)
      when event in [:entitlement_create, :entitlement_update, :entitlement_delete],
      do: Entitlement.new(data)

  def payload(event, data)
      when event in [:game_direct_message_create, :game_direct_message_update],
      do: Message.new(data)

  def payload(_event, data), do: data

  defp integration_type(0), do: :guild
  defp integration_type(1), do: :user
  defp integration_type(other), do: other
end
