defmodule Lingo.Config.Gateway do
  @moduledoc false

  # Validates the :sharding and :gateway options.

  def validate_sharding!(sharding) do
    sharding = Keyword.validate!(sharding, [:count, :ids, :auto_reshard, :session_store])

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

    Keyword.update(sharding, :session_store, nil, &validate_session_store!/1)
  end

  defp validate_session_store!(nil), do: nil

  defp validate_session_store!(module) when is_atom(module),
    do: validate_session_store!({module, []})

  defp validate_session_store!({module, opts}) when is_atom(module) and is_list(opts) do
    Code.ensure_loaded(module)

    unless function_exported?(module, :load, 2) and function_exported?(module, :save, 3),
      do: raise(ArgumentError, "#{inspect(module)} is not a Lingo.Gateway.SessionStore")

    {module, opts}
  end

  defp validate_session_store!(other),
    do: raise(ArgumentError, "invalid :sharding :session_store: #{inspect(other)}")

  def validate_gateway!(false), do: false
  def validate_gateway!(nil), do: validate_gateway!([])

  def validate_gateway!(gateway) do
    gateway = Keyword.validate!(gateway, encoding: :json, compression: :zlib)

    unless gateway[:encoding] in [:json, :etf],
      do: raise(ArgumentError, ":gateway :encoding must be :json or :etf")

    unless gateway[:compression] in [:zlib, :zstd, :none],
      do: raise(ArgumentError, ":gateway :compression must be :zlib, :zstd or :none")

    if gateway[:compression] == :zstd and not Lingo.Gateway.Compression.zstd_available?(),
      do: raise(ArgumentError, ":gateway compression: :zstd needs OTP 28 or later")

    gateway
  end
end
