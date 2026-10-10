defmodule Lingo.Cache.Policy.Options do
  @moduledoc false
  @base %{
    max_entries: :infinity,
    scope_limit: :infinity,
    ttl: :infinity,
    filter: :all,
    keep: :none,
    compact: true,
    compressed: false
  }

  def validate_storage(opts) do
    for key <- [:compact, :compressed], do: boolean!(Keyword.get(opts, key, @base[key]), key)
  end

  def build(resource, options, opts) do
    unless Keyword.keyword?(options), do: invalid!("#{resource} must be a keyword list")

    scope_key =
      if resource == :messages, do: :max_entries_per_channel, else: :max_entries_per_guild

    scoped? = resource in [:channels, :members, :presences, :roles, :voice_states, :messages]

    allowed =
      [:max_entries, :ttl, :filter, :keep, :compact, :compressed] ++
        if(scoped?, do: [scope_key], else: [])

    options = Keyword.validate!(options, allowed)

    default_scope =
      if resource == :messages,
        do: Keyword.get(opts, :max_messages_per_channel, 200),
        else: :infinity

    policy =
      @base
      |> Map.merge(Map.new(Keyword.take(opts, [:compact, :compressed])))
      |> Map.merge(Map.new(Keyword.take(options, Map.keys(@base))))

    policy = Map.put(policy, :scope_limit, Keyword.get(options, scope_key, default_scope))

    for key <- [:max_entries, :scope_limit, :ttl], do: limit!(policy[key], key)

    for key <- [:compact, :compressed], do: boolean!(policy[key], key)

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

  def validate_legacy(value), do: limit!(value, :max_messages_per_channel)

  defp limit!(value, key) do
    unless value == :infinity or (is_integer(value) and value >= 0),
      do: invalid!("#{key} must be :infinity or a non-negative integer")
  end

  defp invalid!(message), do: raise(ArgumentError, ":cache #{message}")

  defp boolean!(value, key) do
    unless is_boolean(value), do: invalid!("#{key} must be a boolean")
  end
end
