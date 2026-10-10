defmodule Lingo.Type.Codes do
  @moduledoc false

  # Discord's numeric codes and the atoms Lingo uses for them. Unknown codes
  # pass through unchanged, so new Discord values never break parsing.

  @enums %{
    channel_type: %{
      0 => :guild_text,
      1 => :dm,
      2 => :guild_voice,
      3 => :group_dm,
      4 => :guild_category,
      5 => :guild_announcement,
      10 => :announcement_thread,
      11 => :public_thread,
      12 => :private_thread,
      13 => :guild_stage_voice,
      14 => :guild_directory,
      15 => :guild_forum,
      16 => :guild_media
    },
    message_type: %{
      0 => :default,
      1 => :recipient_add,
      2 => :recipient_remove,
      3 => :call,
      4 => :channel_name_change,
      5 => :channel_icon_change,
      6 => :channel_pinned_message,
      7 => :user_join,
      8 => :guild_boost,
      9 => :guild_boost_tier_1,
      10 => :guild_boost_tier_2,
      11 => :guild_boost_tier_3,
      12 => :channel_follow_add,
      14 => :guild_discovery_disqualified,
      15 => :guild_discovery_requalified,
      16 => :guild_discovery_grace_period_initial_warning,
      17 => :guild_discovery_grace_period_final_warning,
      18 => :thread_created,
      19 => :reply,
      20 => :chat_input_command,
      21 => :thread_starter_message,
      22 => :guild_invite_reminder,
      23 => :context_menu_command,
      24 => :auto_moderation_action,
      25 => :role_subscription_purchase,
      26 => :interaction_premium_upsell,
      27 => :stage_start,
      28 => :stage_end,
      29 => :stage_speaker,
      31 => :stage_topic,
      32 => :guild_application_premium_subscription,
      36 => :guild_incident_alert_mode_enabled,
      37 => :guild_incident_alert_mode_disabled,
      38 => :guild_incident_report_raid,
      39 => :guild_incident_report_false_alarm,
      44 => :purchase_notification,
      46 => :poll_result
    },
    verification_level: %{0 => :none, 1 => :low, 2 => :medium, 3 => :high, 4 => :very_high},
    default_message_notifications: %{0 => :all_messages, 1 => :only_mentions},
    explicit_content_filter: %{0 => :disabled, 1 => :members_without_roles, 2 => :all_members},
    mfa_level: %{0 => :none, 1 => :elevated},
    nsfw_level: %{0 => :default, 1 => :explicit, 2 => :safe, 3 => :age_restricted},
    premium_tier: %{0 => :none, 1 => :tier_1, 2 => :tier_2, 3 => :tier_3}
  }

  @codes Map.new(@enums, fn {kind, names} -> {kind, Map.new(names, fn {c, n} -> {n, c} end)} end)

  @doc "The atom for a code; `default` when there's no code at all."
  @spec name(atom(), integer() | nil, term()) :: atom() | integer() | term()
  def name(kind, code, default \\ nil)
  def name(_kind, nil, default), do: default
  def name(kind, code, _default), do: Map.get(Map.fetch!(@enums, kind), code, code)

  @doc "The code for an atom (codes pass through)."
  @spec code(atom(), atom() | integer()) :: integer()
  def code(_kind, code) when is_integer(code), do: code
  def code(kind, name) when is_atom(name), do: Map.fetch!(Map.fetch!(@codes, kind), name)
end
