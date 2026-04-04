defmodule Lingo.Api.Guild do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.{Channel, Guild}

  def get(guild_id, opts \\ []) do
    params = if opts[:with_counts], do: %{with_counts: true}, else: nil

    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}", params: params) do
      {:ok, Guild.new(data)}
    end
  end

  def modify(guild_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:patch, "/guilds/#{guild_id}", json: params, reason: opts[:reason]) do
      {:ok, Guild.new(data)}
    end
  end

  def get_preview(guild_id) do
    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/preview") do
      {:ok, Guild.new(data)}
    end
  end

  def get_channels(guild_id) do
    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/channels") do
      {:ok, Enum.map(data, &Channel.new/1)}
    end
  end

  def create_channel(guild_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:post, "/guilds/#{guild_id}/channels",
             json: params,
             reason: opts[:reason]
           ) do
      {:ok, Channel.new(data)}
    end
  end

  def modify_channel_positions(guild_id, positions) do
    Client.request(:patch, "/guilds/#{guild_id}/channels", json: positions)
  end

  def list_active_threads(guild_id) do
    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/threads/active") do
      {:ok,
       %{
         threads: Enum.map(data["threads"] || [], &Channel.new/1),
         members: data["members"] || []
       }}
    end
  end

  def get_voice_regions(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/regions")
  end

  def get_invites(guild_id) do
    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/invites") do
      {:ok, Enum.map(data, &Lingo.Type.Invite.new/1)}
    end
  end

  def get_integrations(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/integrations")
  end

  def delete_integration(guild_id, integration_id, opts \\ []) do
    Client.request(:delete, "/guilds/#{guild_id}/integrations/#{integration_id}",
      reason: opts[:reason]
    )
  end

  def get_widget_settings(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/widget")
  end

  def modify_widget(guild_id, params, opts \\ []) do
    Client.request(:patch, "/guilds/#{guild_id}/widget", json: params, reason: opts[:reason])
  end

  def get_widget(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/widget.json")
  end

  def get_widget_image(guild_id, opts \\ []) do
    params = if opts[:style], do: %{style: opts[:style]}, else: nil
    Client.request(:get, "/guilds/#{guild_id}/widget.png", params: params)
  end

  def get_vanity_url(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/vanity-url")
  end

  def get_welcome_screen(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/welcome-screen")
  end

  def modify_welcome_screen(guild_id, params, opts \\ []) do
    Client.request(:patch, "/guilds/#{guild_id}/welcome-screen",
      json: params,
      reason: opts[:reason]
    )
  end

  def get_onboarding(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/onboarding")
  end

  def modify_onboarding(guild_id, params, opts \\ []) do
    Client.request(:put, "/guilds/#{guild_id}/onboarding", json: params, reason: opts[:reason])
  end

  def get_prune_count(guild_id, opts \\ []) do
    params =
      opts
      |> Keyword.take([:days, :include_roles])
      |> Enum.into(%{})

    Client.request(:get, "/guilds/#{guild_id}/prune", params: params)
  end

  def begin_prune(guild_id, params \\ %{}, opts \\ []) do
    Client.request(:post, "/guilds/#{guild_id}/prune", json: params, reason: opts[:reason])
  end
end
