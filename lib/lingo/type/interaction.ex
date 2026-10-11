defmodule Lingo.Type.Interaction do
  @moduledoc """
  A raw interaction. Bot callbacks get a `Lingo.Context` instead, which wraps it.

  `guild` and `channel` are partial: Discord sends a guild's id, features
  and locale (here `preferred_locale`). `data` is Discord's raw interaction
  data, which `Lingo.Context` parses.
  """

  alias Lingo.Type.{Channel, Entitlement, Guild, Member, Message, Parse, User}

  @type interaction_type ::
          :ping | :application_command | :message_component | :autocomplete | :modal_submit

  @type t :: %__MODULE__{
          id: String.t(),
          application_id: String.t(),
          type: interaction_type(),
          data: map() | nil,
          guild: Guild.t() | nil,
          guild_id: String.t() | nil,
          channel: Channel.t() | nil,
          channel_id: String.t() | nil,
          member: Member.t() | nil,
          user: User.t() | nil,
          token: String.t(),
          version: integer(),
          message: Message.t() | nil,
          app_permissions: String.t() | nil,
          locale: String.t() | nil,
          guild_locale: String.t() | nil,
          entitlements: [Entitlement.t()],
          authorizing_integration_owners: map() | nil,
          context: integer() | nil,
          attachment_size_limit: integer() | nil
        }

  defstruct [
    :id,
    :application_id,
    :type,
    :data,
    :guild,
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

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      application_id: data["application_id"],
      type: Lingo.Type.Codes.name(:interaction_type, data["type"]),
      data: data["data"],
      guild: parse_guild(data["guild"]),
      guild_id: data["guild_id"] || get_in(data, ["guild", "id"]),
      channel: parse_channel(data["channel"], data["guild_id"]),
      channel_id: data["channel_id"] || get_in(data, ["channel", "id"]),
      member: parse_member(data["member"], data["guild_id"]),
      user: User.new(data["user"]),
      token: data["token"],
      version: data["version"] || 1,
      message: parse_message(data["message"], data["guild_id"]),
      app_permissions: data["app_permissions"],
      locale: data["locale"],
      guild_locale: data["guild_locale"],
      entitlements: Parse.list(data["entitlements"], &Entitlement.new/1),
      authorizing_integration_owners: data["authorizing_integration_owners"],
      context: data["context"],
      attachment_size_limit: data["attachment_size_limit"]
    }
  end

  @doc "The user who triggered the interaction, in a guild or a DM."
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

  defp parse_guild(nil), do: nil

  # the partial guild names its preferred locale `locale`
  defp parse_guild(data),
    do: data |> Map.put_new("preferred_locale", data["locale"]) |> Guild.new()

  defp parse_channel(nil, _guild_id), do: nil
  defp parse_channel(data, guild_id), do: data |> Parse.put_guild_id(guild_id) |> Channel.new()

  defp parse_message(nil, _guild_id), do: nil

  defp parse_message(message_data, nil) when is_map(message_data), do: Message.new(message_data)

  defp parse_message(message_data, guild_id) when is_map(message_data) do
    message_data
    |> Map.put_new("guild_id", guild_id)
    |> Message.new()
  end
end
