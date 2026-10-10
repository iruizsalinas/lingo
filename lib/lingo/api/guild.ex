defmodule Lingo.Api.Guild do
  @moduledoc """
  Guilds: settings, channels, integrations, widgets, onboarding and pruning.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.{Channel, Guild}

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

  @doc "Lists a guild's channels, without threads."
  @spec list_channels(Api.id()) :: Api.result([Channel.t()])
  def list_channels(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/channels") |> Client.into(&Channel.new/1)
  end

  @doc "Creates a channel in a guild."
  @spec create_channel(Api.id(), Api.params(), keyword()) :: Api.result(Channel.t())
  def create_channel(guild_id, params, opts \\ []) do
    Client.request(:post, "/guilds/#{guild_id}/channels",
      json: params,
      reason: opts[:reason]
    )
    |> Client.into(&Channel.new/1)
  end

  @doc "Moves channels in a guild, from a list of `%{id:, position:}` maps."
  @spec update_channel_positions(Api.id(), [map()]) :: Api.result()
  def update_channel_positions(guild_id, positions) do
    Client.request(:patch, "/guilds/#{guild_id}/channels", json: positions)
  end

  @doc "Lists a guild's active threads."
  @spec list_active_threads(Api.id()) :: Api.result(%{threads: [Channel.t()], members: [map()]})
  def list_active_threads(guild_id) do
    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/threads/active") do
      {:ok,
       %{
         threads: Enum.map(data["threads"] || [], &Channel.new/1),
         members: data["members"] || []
       }}
    end
  end

  @doc "Lists the voice regions available to a guild."
  @spec list_voice_regions(Api.id()) :: Api.result([map()])
  def list_voice_regions(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/regions")
  end

  @doc "Lists a guild's integrations."
  @spec list_integrations(Api.id()) :: Api.result([map()])
  def list_integrations(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/integrations")
  end

  @doc "Removes an integration from a guild."
  @spec delete_integration(Api.id(), Api.id(), keyword()) :: Api.result()
  def delete_integration(guild_id, integration_id, opts \\ []) do
    Client.request(:delete, "/guilds/#{guild_id}/integrations/#{integration_id}",
      reason: opts[:reason]
    )
  end

  @doc "Fetches a guild's widget settings."
  @spec get_widget_settings(Api.id()) :: Api.result(map())
  def get_widget_settings(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/widget")
  end

  @doc "Edits a guild's widget settings."
  @spec update_widget(Api.id(), Api.params(), keyword()) :: Api.result(map())
  def update_widget(guild_id, params, opts \\ []) do
    Client.request(:patch, "/guilds/#{guild_id}/widget", json: params, reason: opts[:reason])
  end

  @doc "Fetches a guild's public widget."
  @spec get_widget(Api.id()) :: Api.result(map())
  def get_widget(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/widget.json")
  end

  @doc "Fetches a guild's widget as a PNG image. Pass `style:` to pick the banner style."
  @spec get_widget_image(Api.id(), keyword()) :: Api.result(binary())
  def get_widget_image(guild_id, opts \\ []) do
    params = Client.params(opts)
    Client.request(:get, "/guilds/#{guild_id}/widget.png", params: params)
  end

  @doc "Fetches a guild's vanity invite."
  @spec get_vanity_url(Api.id()) :: Api.result(map())
  def get_vanity_url(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/vanity-url")
  end

  @doc "Fetches a guild's welcome screen."
  @spec get_welcome_screen(Api.id()) :: Api.result(map())
  def get_welcome_screen(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/welcome-screen")
  end

  @doc "Edits a guild's welcome screen."
  @spec update_welcome_screen(Api.id(), Api.params(), keyword()) :: Api.result(map())
  def update_welcome_screen(guild_id, params, opts \\ []) do
    Client.request(:patch, "/guilds/#{guild_id}/welcome-screen",
      json: params,
      reason: opts[:reason]
    )
  end

  @doc "Fetches a guild's onboarding settings."
  @spec get_onboarding(Api.id()) :: Api.result(map())
  def get_onboarding(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/onboarding")
  end

  @doc "Edits a guild's onboarding settings."
  @spec update_onboarding(Api.id(), Api.params(), keyword()) :: Api.result(map())
  def update_onboarding(guild_id, params, opts \\ []) do
    Client.request(:put, "/guilds/#{guild_id}/onboarding", json: params, reason: opts[:reason])
  end

  @doc "Pauses invites or DMs in a guild, e.g. during a raid."
  @spec update_incident_actions(Api.id(), Api.params()) :: Api.result(map())
  def update_incident_actions(guild_id, params) do
    Client.request(:put, "/guilds/#{guild_id}/incident-actions", json: params)
  end

  @doc "Counts the members a prune would remove."
  @spec get_prune_count(Api.id(), keyword()) :: Api.result(map())
  def get_prune_count(guild_id, opts \\ []) do
    params =
      Client.params(opts)

    Client.request(:get, "/guilds/#{guild_id}/prune", params: params)
  end

  @doc "Removes inactive members from a guild."
  @spec begin_prune(Api.id(), Api.params(), keyword()) :: Api.result(map())
  def begin_prune(guild_id, params \\ %{}, opts \\ []) do
    Client.request(:post, "/guilds/#{guild_id}/prune", json: params, reason: opts[:reason])
  end
end
