defmodule Lingo.Type.Integration do
  @moduledoc """
  A guild integration: a bot, or a Twitch, YouTube or other connection.

  `type` is Discord's string, such as `"discord"` or `"twitch"`. The sync
  fields (`syncing`, `role_id`, `expire_behavior` and so on) are `nil` for
  bots. `account` and `application` are maps with atom keys.
  """

  alias Lingo.Type.{Parse, User}

  @type account :: %{id: String.t(), name: String.t()}
  @type application :: %{
          id: String.t(),
          name: String.t(),
          icon: String.t() | nil,
          description: String.t(),
          bot: User.t() | nil
        }
  @type t :: %__MODULE__{
          id: String.t(),
          guild_id: String.t() | nil,
          name: String.t(),
          type: String.t(),
          enabled: boolean(),
          syncing: boolean() | nil,
          role_id: String.t() | nil,
          enable_emoticons: boolean() | nil,
          expire_behavior: :remove_role | :kick | integer() | nil,
          expire_grace_period: integer() | nil,
          user: User.t() | nil,
          account: account() | nil,
          synced_at: DateTime.t() | nil,
          subscriber_count: integer() | nil,
          revoked: boolean() | nil,
          application: application() | nil,
          scopes: [String.t()]
        }

  defstruct [
    :id,
    :guild_id,
    :name,
    :type,
    :syncing,
    :role_id,
    :enable_emoticons,
    :expire_behavior,
    :expire_grace_period,
    :user,
    :account,
    :synced_at,
    :subscriber_count,
    :revoked,
    :application,
    enabled: false,
    scopes: []
  ]

  @expire_behaviors %{0 => :remove_role, 1 => :kick}

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      guild_id: data["guild_id"],
      name: data["name"],
      type: data["type"],
      enabled: data["enabled"] || false,
      syncing: data["syncing"],
      role_id: data["role_id"],
      enable_emoticons: data["enable_emoticons"],
      expire_behavior:
        Map.get(@expire_behaviors, data["expire_behavior"], data["expire_behavior"]),
      expire_grace_period: data["expire_grace_period"],
      user: User.new(data["user"]),
      account: account(data["account"]),
      synced_at: Parse.timestamp(data["synced_at"]),
      subscriber_count: data["subscriber_count"],
      revoked: data["revoked"],
      application: application(data["application"]),
      scopes: data["scopes"] || []
    }
  end

  defp account(nil), do: nil
  defp account(data), do: %{id: data["id"], name: data["name"]}

  defp application(nil), do: nil

  defp application(data) do
    %{
      id: data["id"],
      name: data["name"],
      icon: data["icon"],
      description: data["description"],
      bot: User.new(data["bot"])
    }
  end
end
