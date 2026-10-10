defmodule Lingo.Cache.Policy do
  @moduledoc false

  @resources [:guilds, :channels, :users, :members, :presences, :roles, :voice_states, :messages]
  @base %{
    max_entries: :infinity,
    scope_limit: :infinity,
    ttl: :infinity,
    filter: :all,
    keep: :none
  }

  def resources, do: @resources
  def normalize(false), do: %{}
  def normalize(nil), do: normalize([])

  def normalize(:permissions),
    do:
      normalize(
        only: [:guilds, :channels, :roles, :users, :members],
        users: :self,
        members: :self
      )

  def normalize(opts) when is_list(opts) do
    unless Keyword.keyword?(opts), do: invalid!("must be false, :permissions or a keyword list")
    opts = Keyword.validate!(opts, @resources ++ [:only, :enabled, :max_messages_per_channel])

    if Keyword.has_key?(opts, :only) and Keyword.has_key?(opts, :enabled),
      do: invalid!("cannot combine :only and legacy :enabled")

    only = Keyword.get(opts, :only, Keyword.get(opts, :enabled, @resources))

    unless is_list(only) and Enum.all?(only, &(&1 in @resources)),
      do: invalid!(":only/:enabled must be a list of #{inspect(@resources)}")

    if Keyword.has_key?(opts, :max_messages_per_channel),
      do: limit!(opts[:max_messages_per_channel], :max_messages_per_channel)

    # Validate explicit policies even when excluded by :only.
    policies =
      Map.new(@resources, fn resource ->
        {resource, resource_policy(resource, Keyword.get(opts, resource, true), opts)}
      end)

    Map.filter(policies, fn {resource, policy} -> resource in only and policy != false end)
  end

  def normalize(_), do: invalid!("must be false, :permissions or a keyword list")

  defp resource_policy(_, false, _), do: false

  defp resource_policy(resource, :self, opts) when resource in [:users, :members],
    do: resource_policy(resource, [filter: :self, keep: :self], opts)

  defp resource_policy(resource, true, opts), do: resource_policy(resource, [], opts)

  defp resource_policy(resource, options, opts) when is_list(options) do
    unless Keyword.keyword?(options), do: invalid!("#{resource} must be a keyword list")

    scope_key =
      if resource == :messages, do: :max_entries_per_channel, else: :max_entries_per_guild

    scoped? = resource in [:channels, :members, :presences, :roles, :voice_states, :messages]
    allowed = [:max_entries, :ttl, :filter, :keep] ++ if(scoped?, do: [scope_key], else: [])
    options = Keyword.validate!(options, allowed)

    default_scope =
      if resource == :messages,
        do: Keyword.get(opts, :max_messages_per_channel, 200),
        else: :infinity

    policy =
      Map.merge(@base, Map.new(Keyword.take(options, [:max_entries, :ttl, :filter, :keep])))

    policy = Map.put(policy, :scope_limit, Keyword.get(options, scope_key, default_scope))

    for key <- [:max_entries, :scope_limit, :ttl], do: limit!(policy[key], key)

    for key <- [:filter, :keep] do
      value = policy[key]

      unless value in [:all, :none] or (value == :self and resource in [:users, :members]) or
               is_function(value, 2),
             do:
               invalid!(
                 "#{resource} #{key} must be :all, :none, :self (users/members), or a function of arity 2"
               )
    end

    if (policy.max_entries == 0 or policy.scope_limit == 0 or policy.ttl == 0 or
          policy.filter == :none) and
         policy.keep == :none,
       do: false,
       else: policy
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

  def scope(:channels, _, value), do: value.guild_id
  def scope(_, _, _), do: nil

  defp limit!(value, key) do
    unless value == :infinity or (is_integer(value) and value >= 0),
      do: invalid!("#{key} must be :infinity or a non-negative integer")
  end

  defp invalid!(message), do: raise(ArgumentError, ":cache #{message}")
end
