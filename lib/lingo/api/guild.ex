defmodule Lingo.Api.Guild do
  @moduledoc """
  Guilds: settings, channels, integrations, widgets, onboarding and pruning.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client

  alias Lingo.Type.{
    Guild,
    GuildWidget,
    IncidentsData,
    Integration,
    Invite,
    Onboarding,
    VoiceRegion,
    WelcomeScreen
  }

  @doc "Fetches a guild. Pass `with_counts: true` for approximate member and presence counts."
  @spec get(Api.id(), keyword()) :: Api.result(Guild.t())
  def get(guild_id, opts \\ []) do
    params = Client.params(opts)

    Client.request(:get, "/guilds/#{guild_id}", params: params) |> Client.into(&Guild.new/1)
  end

  @doc "Edits a guild's settings."
  @spec update(Api.id(), Api.params(), keyword()) :: Api.result(Guild.t())
  def update(guild_id, params, opts \\ []) do
    Client.request(:patch, "/guilds/#{guild_id}", json: params, reason: opts[:reason])
    |> Client.into(&Guild.new/1)
  end

  @doc "Fetches the public preview of a discoverable guild."
  @spec get_preview(Api.id()) :: Api.result(Guild.t())
  def get_preview(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/preview") |> Client.into(&Guild.new/1)
  end

  @doc "Lists the voice regions available to a guild, with VIP ones when it has them."
  @spec list_voice_regions(Api.id()) :: Api.result([VoiceRegion.t()])
  def list_voice_regions(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/regions") |> Client.into(&VoiceRegion.new/1)
  end

  @doc "Lists a guild's integrations."
  @spec list_integrations(Api.id()) :: Api.result([Integration.t()])
  def list_integrations(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/integrations")
    |> Client.into(&Integration.new(Map.put(&1, "guild_id", guild_id)))
  end

  @doc "Removes an integration from a guild."
  @spec delete_integration(Api.id(), Api.id(), keyword()) :: Api.result()
  def delete_integration(guild_id, integration_id, opts \\ []) do
    Client.request(:delete, "/guilds/#{guild_id}/integrations/#{integration_id}",
      reason: opts[:reason]
    )
  end

  @typedoc "Whether a guild's widget is enabled, and the channel its invite leads to."
  @type widget_settings :: %{enabled: boolean(), channel_id: Api.id() | nil}

  @doc "Fetches a guild's widget settings."
  @spec get_widget_settings(Api.id()) :: Api.result(widget_settings())
  def get_widget_settings(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/widget") |> Client.into(&widget_settings/1)
  end

  @doc "Edits a guild's widget settings: `:enabled` and `:channel_id`."
  @spec update_widget(Api.id(), Api.params(), keyword()) :: Api.result(widget_settings())
  def update_widget(guild_id, params, opts \\ []) do
    Client.request(:patch, "/guilds/#{guild_id}/widget", json: params, reason: opts[:reason])
    |> Client.into(&widget_settings/1)
  end

  defp widget_settings(data),
    do: %{enabled: data["enabled"] || false, channel_id: data["channel_id"]}

  @doc "Fetches a guild's public widget."
  @spec get_widget(Api.id()) :: Api.result(GuildWidget.t())
  def get_widget(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/widget.json") |> Client.into(&GuildWidget.new/1)
  end

  @doc "Fetches a guild's widget as a PNG image. Pass `style:` to pick the banner style."
  @spec get_widget_image(Api.id(), keyword()) :: Api.result(binary())
  def get_widget_image(guild_id, opts \\ []) do
    params = Client.params(opts)
    Client.request(:get, "/guilds/#{guild_id}/widget.png", params: params)
  end

  @doc """
  Fetches a guild's vanity invite: its `code` (`nil` when none is set) and
  `uses`.
  """
  @spec get_vanity_url(Api.id()) :: Api.result(Invite.t())
  def get_vanity_url(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/vanity-url") |> Client.into(&Invite.new/1)
  end

  @doc "Fetches a guild's welcome screen."
  @spec get_welcome_screen(Api.id()) :: Api.result(WelcomeScreen.t())
  def get_welcome_screen(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/welcome-screen")
    |> Client.into(&WelcomeScreen.new/1)
  end

  @doc "Edits a guild's welcome screen: `:enabled`, `:welcome_channels` and `:description`."
  @spec update_welcome_screen(Api.id(), Api.params(), keyword()) ::
          Api.result(WelcomeScreen.t())
  def update_welcome_screen(guild_id, params, opts \\ []) do
    Client.request(:patch, "/guilds/#{guild_id}/welcome-screen",
      json: params,
      reason: opts[:reason]
    )
    |> Client.into(&WelcomeScreen.new/1)
  end

  @doc "Fetches a guild's onboarding settings."
  @spec get_onboarding(Api.id()) :: Api.result(Onboarding.t())
  def get_onboarding(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/onboarding") |> Client.into(&Onboarding.new/1)
  end

  @doc """
  Edits a guild's onboarding settings: `:prompts`, `:default_channel_ids`,
  `:enabled` and `:mode`, with Discord's fields and numbers.
  """
  @spec update_onboarding(Api.id(), Api.params(), keyword()) :: Api.result(Onboarding.t())
  def update_onboarding(guild_id, params, opts \\ []) do
    Client.request(:put, "/guilds/#{guild_id}/onboarding", json: params, reason: opts[:reason])
    |> Client.into(&Onboarding.new/1)
  end

  @doc """
  Pauses invites or DMs in a guild, e.g. during a raid: `:invites_disabled_until`
  and `:dms_disabled_until`, up to 24 hours ahead, or `nil` to lift a pause.
  """
  @spec update_incident_actions(Api.id(), Api.params()) :: Api.result(IncidentsData.t())
  def update_incident_actions(guild_id, params) do
    Client.request(:put, "/guilds/#{guild_id}/incident-actions", json: params)
    |> Client.into(&IncidentsData.new/1)
  end

  @doc """
  Counts the members a prune would remove. Options: `:days` (1 to 30) and
  `:include_roles` (role ids whose members may be pruned too).
  """
  @spec get_prune_count(Api.id(), keyword()) :: Api.result(non_neg_integer())
  def get_prune_count(guild_id, opts \\ []) do
    params = Client.params(opts) |> Map.replace_lazy(:include_roles, &join_ids/1)

    Client.request(:get, "/guilds/#{guild_id}/prune", params: params)
    |> Client.into(& &1["pruned"])
  end

  @doc """
  Removes inactive members from a guild, returning how many. Params: `:days`,
  `:include_roles`, and `compute_prune_count: false` for large guilds, which
  returns `nil` instead.
  """
  @spec begin_prune(Api.id(), Api.params(), keyword()) :: Api.result(non_neg_integer() | nil)
  def begin_prune(guild_id, params \\ %{}, opts \\ []) do
    Client.request(:post, "/guilds/#{guild_id}/prune", json: params, reason: opts[:reason])
    |> Client.into(& &1["pruned"])
  end

  # the query string takes the roles comma separated
  defp join_ids(ids) when is_list(ids), do: Enum.join(ids, ",")
  defp join_ids(ids), do: ids
end
