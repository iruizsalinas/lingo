defmodule Lingo.Config.Gateway do
  @moduledoc false

  # Validates the :sharding and :gateway options. A session store goes under
  # :gateway: there's none without a gateway connection.

  def validate_sharding!(sharding) do
    if Keyword.has_key?(sharding, :session_store),
      do: raise(ArgumentError, ":session_store moved from :sharding to :gateway")

    sharding = Keyword.validate!(sharding, [:count, :ids, :auto_reshard])

    if Keyword.has_key?(sharding, :ids) and not Keyword.has_key?(sharding, :count) do
      raise ArgumentError, ":sharding :ids requires an explicit :count"
    end

    case sharding[:auto_reshard] do
      auto when auto in [nil, false, true] ->
        :ok

      ms when is_integer(ms) and ms > 0 ->
        :ok

      other ->
        raise ArgumentError,
              ":sharding :auto_reshard must be a boolean or ms, got: #{inspect(other)}"
    end

    sharding
  end

  defp validate_session_store!(nil), do: nil

  defp validate_session_store!(module) when is_atom(module),
    do: validate_session_store!({module, []})

  defp validate_session_store!({module, opts}) when is_atom(module) and is_list(opts) do
    Code.ensure_loaded(module)

    unless function_exported?(module, :load, 2) and function_exported?(module, :save, 3) and
             function_exported?(module, :delete, 4),
           do: raise(ArgumentError, "#{inspect(module)} is not a Lingo.Gateway.SessionStore")

    {module, opts}
  end

  defp validate_session_store!(other),
    do: raise(ArgumentError, "invalid :gateway :session_store: #{inspect(other)}")

  def validate_gateway!(false), do: false
  def validate_gateway!(nil), do: validate_gateway!([])

  def validate_gateway!(gateway) do
    gateway = Keyword.validate!(gateway, [:session_store, encoding: :json, compression: :zlib])

    unless gateway[:encoding] in [:json, :etf],
      do: raise(ArgumentError, ":gateway :encoding must be :json or :etf")

    unless gateway[:compression] in [:zlib, :zstd, :none],
      do: raise(ArgumentError, ":gateway :compression must be :zlib, :zstd or :none")

    if gateway[:compression] == :zstd and not Lingo.Gateway.Compression.zstd_available?(),
      do: raise(ArgumentError, ":gateway compression: :zstd needs OTP 28 or later")

    if Keyword.has_key?(gateway, :session_store),
      do: Keyword.update!(gateway, :session_store, &validate_session_store!/1),
      else: gateway
  end
end
