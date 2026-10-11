defmodule Lingo.Type.Application do
  @moduledoc """
  An application: the bot's own, from `Lingo.Api.Application.get_current/0`,
  or a partial one inside messages, attachments and invites.

  `team`, `install_params` and the values of `integration_types_config` are
  maps with atom keys. `integration_types_config` is keyed by `:guild` and
  `:user` (Discord's `0` and `1`), and `event_webhooks_status` is
  `:disabled`, `:enabled` or `:disabled_by_discord`. `flags` holds the
  legacy flags; `flags_new` is the full bitfield, as a string.
  """

  alias Lingo.Type.{Guild, Parse, User}

  @type install_params :: %{scopes: [String.t()], permissions: String.t()}
  @type team_member :: %{
          membership_state: :invited | :accepted | integer(),
          team_id: String.t(),
          user: User.t(),
          role: String.t()
        }
  @type team :: %{
          id: String.t(),
          name: String.t(),
          icon: String.t() | nil,
          owner_user_id: String.t(),
          members: [team_member()]
        }
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          icon: String.t() | nil,
          description: String.t(),
          rpc_origins: [String.t()],
          bot_public: boolean(),
          bot_require_code_grant: boolean(),
          bot: User.t() | nil,
          terms_of_service_url: String.t() | nil,
          privacy_policy_url: String.t() | nil,
          owner: User.t() | nil,
          verify_key: String.t(),
          team: team() | nil,
          guild_id: String.t() | nil,
          guild: Guild.t() | nil,
          primary_sku_id: String.t() | nil,
          slug: String.t() | nil,
          cover_image: String.t() | nil,
          flags: integer(),
          flags_new: String.t() | nil,
          approximate_guild_count: integer() | nil,
          approximate_user_install_count: integer() | nil,
          approximate_user_authorization_count: integer() | nil,
          redirect_uris: [String.t()],
          interactions_endpoint_url: String.t() | nil,
          role_connections_verification_url: String.t() | nil,
          event_webhooks_url: String.t() | nil,
          event_webhooks_status: :disabled | :enabled | :disabled_by_discord | integer() | nil,
          event_webhooks_types: [String.t()],
          tags: [String.t()],
          install_params: install_params() | nil,
          integration_types_config:
            %{optional(:guild | :user) => %{oauth2_install_params: install_params() | nil}}
            | nil,
          custom_install_url: String.t() | nil
        }

  defstruct [
    :id,
    :name,
    :icon,
    :description,
    :bot,
    :terms_of_service_url,
    :privacy_policy_url,
    :owner,
    :verify_key,
    :team,
    :guild_id,
    :guild,
    :primary_sku_id,
    :slug,
    :cover_image,
    :flags_new,
    :approximate_guild_count,
    :approximate_user_install_count,
    :approximate_user_authorization_count,
    :interactions_endpoint_url,
    :role_connections_verification_url,
    :event_webhooks_url,
    :event_webhooks_status,
    :install_params,
    :integration_types_config,
    :custom_install_url,
    rpc_origins: [],
    bot_public: false,
    bot_require_code_grant: false,
    flags: 0,
    redirect_uris: [],
    event_webhooks_types: [],
    tags: []
  ]

  @webhook_statuses %{1 => :disabled, 2 => :enabled, 3 => :disabled_by_discord}
  @integration_types %{"0" => :guild, "1" => :user}
  @membership_states %{1 => :invited, 2 => :accepted}

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    struct(Parse.fields(__MODULE__, data),
      bot: User.new(data["bot"]),
      owner: User.new(data["owner"]),
      team: team(data["team"]),
      guild: Guild.new(data["guild"]),
      event_webhooks_status:
        Map.get(@webhook_statuses, data["event_webhooks_status"], data["event_webhooks_status"]),
      install_params: install_params(data["install_params"]),
      integration_types_config: integration_types_config(data["integration_types_config"])
    )
  end

  defp team(nil), do: nil

  defp team(data) do
    %{
      id: data["id"],
      name: data["name"],
      icon: data["icon"],
      owner_user_id: data["owner_user_id"],
      members: Parse.list(data["members"], &team_member/1)
    }
  end

  defp team_member(data) do
    %{
      membership_state:
        Map.get(@membership_states, data["membership_state"], data["membership_state"]),
      team_id: data["team_id"],
      user: User.new(data["user"]),
      role: data["role"]
    }
  end

  defp install_params(nil), do: nil

  defp install_params(data),
    do: %{scopes: data["scopes"] || [], permissions: data["permissions"]}

  defp integration_types_config(nil), do: nil

  defp integration_types_config(config) do
    Map.new(config, fn {type, data} ->
      {Map.get(@integration_types, type, type),
       %{oauth2_install_params: install_params((data || %{})["oauth2_install_params"])}}
    end)
  end
end
