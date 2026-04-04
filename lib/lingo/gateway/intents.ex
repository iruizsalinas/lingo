defmodule Lingo.Gateway.Intents do
  @moduledoc false

  import Bitwise

  @intents %{
    guilds: 1 <<< 0,
    guild_members: 1 <<< 1,
    guild_moderation: 1 <<< 2,
    guild_expressions: 1 <<< 3,
    guild_integrations: 1 <<< 4,
    guild_webhooks: 1 <<< 5,
    guild_invites: 1 <<< 6,
    guild_voice_states: 1 <<< 7,
    guild_presences: 1 <<< 8,
    guild_messages: 1 <<< 9,
    guild_message_reactions: 1 <<< 10,
    guild_message_typing: 1 <<< 11,
    direct_messages: 1 <<< 12,
    direct_message_reactions: 1 <<< 13,
    direct_message_typing: 1 <<< 14,
    message_content: 1 <<< 15,
    guild_scheduled_events: 1 <<< 16,
    auto_moderation_configuration: 1 <<< 20,
    auto_moderation_execution: 1 <<< 21,
    guild_message_polls: 1 <<< 24,
    direct_message_polls: 1 <<< 25
  }

  @privileged [:guild_presences, :guild_members, :message_content]

  @non_privileged Map.keys(@intents) -- @privileged

  @spec resolve([atom()] | integer()) :: integer()
  def resolve(intents) when is_integer(intents), do: intents

  def resolve(intents) when is_list(intents) do
    Enum.reduce(intents, 0, fn intent, acc ->
      case Map.fetch(@intents, intent) do
        {:ok, value} -> Bitwise.bor(acc, value)
        :error -> raise ArgumentError, "unknown intent: #{inspect(intent)}"
      end
    end)
  end

  @spec all :: integer()
  def all, do: resolve(Map.keys(@intents))

  @spec non_privileged :: integer()
  def non_privileged, do: resolve(@non_privileged)

  @spec privileged?(atom()) :: boolean()
  def privileged?(intent), do: intent in @privileged

  @spec names :: [atom()]
  def names, do: Map.keys(@intents)
end
