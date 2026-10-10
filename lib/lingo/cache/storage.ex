defmodule Lingo.Cache.Storage do
  @moduledoc false

  # Only known Discord structs are compacted. Default elision is lossless and
  # never applies to arbitrary maps or other structs (notably DateTime).
  alias Lingo.Type

  @modules [
    Type.Guild,
    Type.Channel,
    Type.User,
    Type.Member,
    Type.Role,
    Type.Presence,
    Type.VoiceState,
    Type.Message,
    Type.Attachment,
    Type.Embed,
    Type.Emoji,
    Type.Sticker,
    Type.Reaction,
    Type.Overwrite,
    Type.Activity
  ]
  @defaults Map.new(@modules, fn module ->
              Code.ensure_compiled!(module)
              {module, module.__struct__()}
            end)

  def table(policy, managed? \\ false), do: :ets.new(__MODULE__, options(policy, managed?))

  defp options(policy, managed?) do
    access = if managed?, do: :protected, else: :public
    [:set, access, read_concurrency: true] ++ if(policy.compressed, do: [:compressed], else: [])
  end

  def encode(value, %{compact: false}), do: value
  def encode(value, _), do: compact(value)

  defp compact(%module{} = value) when module in @modules do
    defaults = Map.fetch!(@defaults, module)

    Enum.reduce(Map.to_list(value), %{__struct__: module}, fn
      {:__struct__, _}, acc ->
        acc

      {key, field}, acc ->
        if Map.has_key?(defaults, key) and field === Map.fetch!(defaults, key),
          do: acc,
          else: Map.put(acc, key, compact(field))
    end)
  end

  defp compact(%_{} = value), do: value

  defp compact(value) when is_map(value),
    do: Map.new(value, fn {key, field} -> {key, compact(field)} end)

  defp compact(value) when is_list(value), do: Enum.map(value, &compact/1)
  defp compact(value), do: value

  def decode(value, %{compact: false}), do: value
  def decode(value, _), do: expand(value)

  # A concurrent write may replace the version selected for deletion.
  def delete_version(table, key, value, policy) do
    stored = encode(value, policy)
    :ets.select_delete(table, [{{key, :"$1"}, [{:"=:=", :"$1", {:const, stored}}], [true]}])
  end

  defp expand(%{__struct__: module} = value) when module in @modules do
    Enum.reduce(Map.to_list(value), Map.fetch!(@defaults, module), fn
      {:__struct__, _}, acc -> acc
      {key, field}, acc -> Map.put(acc, key, expand(field))
    end)
  end

  defp expand(%_{} = value), do: value

  defp expand(value) when is_map(value),
    do: Map.new(value, fn {key, field} -> {key, expand(field)} end)

  defp expand(value) when is_list(value), do: Enum.map(value, &expand/1)
  defp expand(value), do: value
end
