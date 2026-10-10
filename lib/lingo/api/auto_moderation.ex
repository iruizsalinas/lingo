defmodule Lingo.Api.AutoModeration do
  @moduledoc """
  Auto moderation rules.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.AutoModerationRule

  @doc "Lists a guild's auto moderation rules."
  @spec list_rules(Api.id()) :: Api.result([AutoModerationRule.t()])
  def list_rules(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/auto-moderation/rules")
    |> Client.into(&AutoModerationRule.new/1)
  end

  @doc "Fetches an auto moderation rule."
  @spec get_rule(Api.id(), Api.id()) :: Api.result(AutoModerationRule.t())
  def get_rule(guild_id, rule_id) do
    Client.request(:get, "/guilds/#{guild_id}/auto-moderation/rules/#{rule_id}")
    |> Client.into(&AutoModerationRule.new/1)
  end

  @doc "Creates an auto moderation rule."
  @spec create_rule(Api.id(), Api.params(), keyword()) :: Api.result(AutoModerationRule.t())
  def create_rule(guild_id, params, opts \\ []) do
    Client.request(:post, "/guilds/#{guild_id}/auto-moderation/rules",
      json: params,
      reason: opts[:reason]
    )
    |> Client.into(&AutoModerationRule.new/1)
  end

  @doc "Edits an auto moderation rule."
  @spec update_rule(Api.id(), Api.id(), Api.params(), keyword()) ::
          Api.result(AutoModerationRule.t())
  def update_rule(guild_id, rule_id, params, opts \\ []) do
    Client.request(:patch, "/guilds/#{guild_id}/auto-moderation/rules/#{rule_id}",
      json: params,
      reason: opts[:reason]
    )
    |> Client.into(&AutoModerationRule.new/1)
  end

  @doc "Deletes an auto moderation rule."
  @spec delete_rule(Api.id(), Api.id(), keyword()) :: Api.result()
  def delete_rule(guild_id, rule_id, opts \\ []) do
    Client.request(:delete, "/guilds/#{guild_id}/auto-moderation/rules/#{rule_id}",
      reason: opts[:reason]
    )
  end
end
