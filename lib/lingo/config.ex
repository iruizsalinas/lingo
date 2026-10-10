defmodule Lingo.Config do
  @moduledoc false

  # Validates and normalizes the options a bot is started with; the gateway's
  # are in Config.Gateway.

  alias Lingo.Config.Gateway

  @defaults [
    :bot,
    :token,
    :name,
    intents: [:guilds, :guild_messages],
    cache: [],
    sharding: [],
    gateway: [],
    endpoint: nil,
    presence: [],
    rate_limit: [],
    rest: [],
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
    validate_rest!(opts[:rest] || [])
    validate_register_commands!(opts[:register_commands])
    Lingo.Cache.Policy.normalize(opts[:cache])

    opts
    |> Keyword.put(:name, opts[:name] || opts[:bot])
    |> Keyword.put(:sharding, Gateway.validate_sharding!(opts[:sharding] || []))
    |> Keyword.put(:gateway, Gateway.validate_gateway!(opts[:gateway]))
    |> Keyword.put(:endpoint, validate_endpoint!(opts[:endpoint]))
  end

  defp validate_endpoint!(nil), do: nil

  defp validate_endpoint!(endpoint) when is_list(endpoint) do
    endpoint =
      Keyword.validate!(endpoint, [
        :public_key,
        :port,
        :ip,
        interactions_path: "/interactions",
        events_path: "/events"
      ])

    key = endpoint[:public_key]

    unless is_binary(key) and match?({:ok, <<_::binary-32>>}, Base.decode16(key, case: :mixed)),
      do: raise(ArgumentError, ":endpoint :public_key must be the app's hex public key")

    port = endpoint[:port]

    unless port == nil or (is_integer(port) and port in 0..65_535),
      do: raise(ArgumentError, ":endpoint :port must be a port number")

    endpoint
  end

  defp validate_endpoint!(other),
    do: raise(ArgumentError, "invalid :endpoint: #{inspect(other)}")

  defp validate_max_wait!(nil), do: :ok
  defp validate_max_wait!(:infinity), do: :ok
  defp validate_max_wait!(ms) when is_integer(ms) and ms >= 0, do: :ok

  defp validate_max_wait!(other),
    do:
      raise(
        ArgumentError,
        ":rate_limit :max_wait must be :infinity or ms, got: #{inspect(other)}"
      )

  defp validate_rest!(rest) do
    rest = Keyword.validate!(rest, [:base_url])

    case rest[:base_url] do
      nil ->
        :ok

      url when is_binary(url) ->
        unless String.starts_with?(url, ["http://", "https://"]) and
                 not String.ends_with?(url, "/"),
               do:
                 raise(
                   ArgumentError,
                   ":rest :base_url must be an http(s) URL without a trailing /"
                 )

      other ->
        raise ArgumentError, ":rest :base_url must be a string, got: #{inspect(other)}"
    end
  end

  defp validate_register_commands!(scope) when scope in [false, :global], do: :ok
  defp validate_register_commands!({:guild, _guild_id}), do: :ok
  defp validate_register_commands!({:guilds, guild_ids}) when is_list(guild_ids), do: :ok

  defp validate_register_commands!(other),
    do: raise(ArgumentError, "invalid :register_commands: #{inspect(other)}")
end
