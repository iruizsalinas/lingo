defmodule Lingo.Cache.Policy do
  @moduledoc false

  alias Lingo.Cache.Policy.Options

  @resources [:guilds, :channels, :users, :members, :presences, :roles, :voice_states, :messages]
  def resources, do: @resources
  def normalize(false), do: %{}
  def normalize(nil), do: normalize([])

  # Retained for callers of the earlier API as an explicit opt-in.
  def normalize(:permissions),
    do: normalize(guilds: true, channels: true, roles: true, users: :self, members: :self)

  def normalize(opts) when is_list(opts) do
    unless Keyword.keyword?(opts), do: invalid!("must be false, :permissions or a keyword list")

    opts =
      Keyword.validate!(
        opts,
        @resources ++ [:only, :enabled, :max_messages_per_channel, :compact, :compressed]
      )

    Options.validate_storage(opts)

    if Keyword.has_key?(opts, :only) and Keyword.has_key?(opts, :enabled),
      do: invalid!("cannot combine :only and legacy :enabled")

    only = Keyword.get(opts, :only, Keyword.get(opts, :enabled, @resources))

    unless is_list(only) and Enum.all?(only, &(&1 in @resources)),
      do: invalid!(":only/:enabled must be a list of #{inspect(@resources)}")

    if Keyword.has_key?(opts, :max_messages_per_channel),
      do: Options.validate_legacy(opts[:max_messages_per_channel])

    # Validate explicit policies even when excluded by :only.
    policies =
      Map.new(@resources, fn resource ->
        fallback = default(resource, opts)
        {resource, resource_policy(resource, Keyword.get(opts, resource, fallback), opts)}
      end)

    Map.filter(policies, fn {resource, policy} -> resource in only and policy != false end)
  end

  def normalize(_), do: invalid!("must be false, :permissions or a keyword list")

  defp default(resource, opts) do
    selected? = Keyword.has_key?(opts, :only) or Keyword.has_key?(opts, :enabled)
    legacy_messages? = resource == :messages and Keyword.has_key?(opts, :max_messages_per_channel)
    selected? or legacy_messages?
  end

  defp resource_policy(_, false, _), do: false

  defp resource_policy(resource, :self, opts) when resource in [:users, :members],
    do: Options.build(resource, [filter: :self, keep: :self], opts)

  defp resource_policy(resource, true, opts), do: Options.build(resource, [], opts)

  defp resource_policy(resource, options, opts) when is_list(options) do
    unless Keyword.keyword?(options), do: invalid!("#{resource} must be a keyword list")
    Options.build(resource, options, opts)
  end

  defp resource_policy(resource, _, _), do: invalid!("invalid policy for #{resource}")

  def managed?(policy),
    do:
      policy.max_entries != :infinity or policy.scope_limit != :infinity or
        policy.ttl != :infinity or policy.keep != :none

  def context(resource, key) do
    %{
      bot: Lingo.Instance.current(),
      user_id: Lingo.Instance.get(:user_id),
      resource: resource,
      key: key
    }
  end

  def decision(policy, value, context) do
    kept? = matches?(policy.keep, value, context)
    {kept? or matches?(policy.filter, value, context), kept?}
  end

  defp matches?(:all, _, _), do: true
  defp matches?(:none, _, _), do: false

  defp matches?(:self, value, %{user_id: id}) when id != nil,
    do: Map.get(value, :id) == id or get_in(value, [Access.key(:user), Access.key(:id)]) == id

  defp matches?(:self, _, _), do: false
  defp matches?(fun, value, context), do: fun.(value, context) == true

  def scope(:messages, {channel_id, _}, _), do: channel_id

  def scope(resource, {guild_id, _}, _)
      when resource in [:members, :roles, :presences, :voice_states], do: guild_id

  def scope(:channels, _, value), do: Map.get(value, :guild_id)
  def scope(_, _, _), do: nil

  defp invalid!(message), do: raise(ArgumentError, ":cache #{message}")
end
