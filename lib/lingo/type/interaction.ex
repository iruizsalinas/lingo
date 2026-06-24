defmodule Lingo.Type.Interaction do
  @moduledoc false

  alias Lingo.Type.{Member, Message, User}

  @type interaction_type ::
          :ping | :application_command | :message_component | :autocomplete | :modal_submit

  @type t :: %__MODULE__{
          id: String.t(),
          application_id: String.t(),
          type: interaction_type(),
          data: map() | nil,
          guild_id: String.t() | nil,
          channel: map() | nil,
          channel_id: String.t() | nil,
          member: Member.t() | nil,
          user: User.t() | nil,
          token: String.t(),
          version: integer(),
          message: Message.t() | nil,
          app_permissions: String.t() | nil,
          locale: String.t() | nil,
          guild_locale: String.t() | nil,
          entitlements: [map()],
          authorizing_integration_owners: map() | nil,
          context: integer() | nil,
          attachment_size_limit: integer() | nil
        }

  defstruct [
    :id,
    :application_id,
    :type,
    :data,
    :guild_id,
    :channel,
    :channel_id,
    :member,
    :user,
    :token,
    :message,
    :app_permissions,
    :locale,
    :guild_locale,
    :authorizing_integration_owners,
    :context,
    :attachment_size_limit,
    version: 1,
    entitlements: []
  ]

  @interaction_types %{
    1 => :ping,
    2 => :application_command,
    3 => :message_component,
    4 => :autocomplete,
    5 => :modal_submit
  }

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      application_id: data["application_id"],
      type: Map.get(@interaction_types, data["type"], data["type"]),
      data: data["data"],
      guild_id: data["guild_id"],
      channel: data["channel"],
      channel_id: data["channel_id"],
      member: parse_member(data["member"], data["guild_id"]),
      user: User.new(data["user"]),
      token: data["token"],
      version: data["version"] || 1,
      message: Message.new(data["message"]),
      app_permissions: data["app_permissions"],
      locale: data["locale"],
      guild_locale: data["guild_locale"],
      entitlements: data["entitlements"] || [],
      authorizing_integration_owners: data["authorizing_integration_owners"],
      context: data["context"],
      attachment_size_limit: data["attachment_size_limit"]
    }
  end

  @spec author(t()) :: User.t() | nil
  def author(%__MODULE__{member: %Member{user: user}}) when not is_nil(user), do: user
  def author(%__MODULE__{user: user}), do: user

  defp parse_member(nil, _guild_id), do: nil

  defp parse_member(member_data, nil) when is_map(member_data), do: Member.new(member_data)

  defp parse_member(member_data, guild_id) when is_map(member_data) do
    member_data
    |> Map.put("guild_id", guild_id)
    |> Member.new()
  end
end
