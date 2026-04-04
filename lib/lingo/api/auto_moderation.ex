defmodule Lingo.Api.AutoModeration do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.AutoModerationRule

  def list_rules(guild_id) do
    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/auto-moderation/rules") do
      {:ok, Enum.map(data, &AutoModerationRule.new/1)}
    end
  end

  def get_rule(guild_id, rule_id) do
    with {:ok, data} <-
           Client.request(:get, "/guilds/#{guild_id}/auto-moderation/rules/#{rule_id}") do
      {:ok, AutoModerationRule.new(data)}
    end
  end

  def create_rule(guild_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:post, "/guilds/#{guild_id}/auto-moderation/rules",
             json: params,
             reason: opts[:reason]
           ) do
      {:ok, AutoModerationRule.new(data)}
    end
  end

  def modify_rule(guild_id, rule_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:patch, "/guilds/#{guild_id}/auto-moderation/rules/#{rule_id}",
             json: params,
             reason: opts[:reason]
           ) do
      {:ok, AutoModerationRule.new(data)}
    end
  end

  def delete_rule(guild_id, rule_id, opts \\ []) do
    Client.request(:delete, "/guilds/#{guild_id}/auto-moderation/rules/#{rule_id}",
      reason: opts[:reason]
    )
  end
end
