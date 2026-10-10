defmodule Lingo.Config do
  @moduledoc false

  # Validates and normalizes the options a bot is started with.

  @defaults [
    :bot,
    :token,
    :name,
    intents: [:guilds, :guild_messages],
    cache: [],
    sharding: [],
    presence: [],
    rate_limit: [],
    register_commands: false
  ]

  @spec validate!(keyword()) :: keyword()
  def validate!(opts) do
    opts = Keyword.validate!(opts, @defaults)

    for key <- [:bot, :token], is_nil(opts[key]) do
      raise ArgumentError, "Lingo needs the #{inspect(key)} option"
    end

    unless is_atom(opts[:bot]), do: raise(ArgumentError, ":bot must be a module")

    validate_max_wait!(get_in(opts, [:rate_limit, :max_wait]))
    validate_sharding!(opts[:sharding] || [])
    validate_register_commands!(opts[:register_commands])
    Lingo.Cache.Policy.normalize(opts[:cache])

    Keyword.put(opts, :name, opts[:name] || opts[:bot])
  end

  defp validate_max_wait!(nil), do: :ok
  defp validate_max_wait!(:infinity), do: :ok
  defp validate_max_wait!(ms) when is_integer(ms) and ms >= 0, do: :ok

  defp validate_max_wait!(other),
    do:
      raise(
        ArgumentError,
        ":rate_limit :max_wait must be :infinity or ms, got: #{inspect(other)}"
      )

  defp validate_sharding!(sharding) do
    if Keyword.has_key?(sharding, :ids) and not Keyword.has_key?(sharding, :count) do
      raise ArgumentError, ":sharding :ids requires an explicit :count"
    end
  end

  defp validate_register_commands!(scope) when scope in [false, :global], do: :ok
  defp validate_register_commands!({:guild, _guild_id}), do: :ok
  defp validate_register_commands!({:guilds, guild_ids}) when is_list(guild_ids), do: :ok

  defp validate_register_commands!(other),
    do: raise(ArgumentError, "invalid :register_commands: #{inspect(other)}")
end
