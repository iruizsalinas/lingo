defmodule Lingo.Type.Parse do
  @moduledoc false

  # Shared pieces of the types' new/1 constructors.

  @doc """
  A struct with every field copied from the string key of the same name.
  Missing or nil values keep the struct's default.
  """
  @spec fields(module(), map()) :: struct()
  def fields(module, data) do
    defaults = Map.from_struct(module.__struct__())

    values =
      for {key, default} <- defaults, into: %{} do
        case Map.get(data, Atom.to_string(key)) do
          nil -> {key, default}
          value -> {key, value}
        end
      end

    struct(module, values)
  end

  @doc "Discord's ISO8601 timestamps as DateTimes; anything else is kept as is."
  @spec timestamp(term()) :: DateTime.t() | term()
  def timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> value
    end
  end

  def timestamp(value), do: value

  @doc "Unix timestamps in seconds, as some gateway events send them, as DateTimes."
  @spec unix(term()) :: DateTime.t() | term()
  def unix(seconds) when is_integer(seconds), do: DateTime.from_unix!(seconds)
  def unix(value), do: value

  @doc "Maps `fun` over a list that may be missing."
  @spec list([term()] | nil, (term() -> term())) :: [term()]
  def list(nil, _fun), do: []
  def list(items, fun) when is_list(items), do: Enum.map(items, fun)

  @doc "Adds the guild id to nested data that doesn't carry its own."
  @spec put_guild_id(map(), String.t() | nil) :: map()
  def put_guild_id(data, nil), do: data
  def put_guild_id(data, guild_id), do: Map.put(data, "guild_id", guild_id)
end
