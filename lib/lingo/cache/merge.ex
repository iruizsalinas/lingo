defmodule Lingo.Cache.Merge do
  @moduledoc false

  # Folds partial updates into cached structs.

  alias Lingo.Type.{Member, Message}

  @spec member(Member.t(), map()) :: Member.t()
  def member(%Member{} = existing, data) when is_map(data) do
    parsed = Member.new(data)

    Enum.reduce(Map.keys(Map.from_struct(existing)), existing, fn field, acc ->
      if Map.has_key?(data, Atom.to_string(field)),
        do: Map.put(acc, field, Map.get(parsed, field)),
        else: acc
    end)
  end

  # only the fields the update carries change
  @spec message(Message.t(), map()) :: Message.t()
  def message(%Message{} = existing, data) when is_map(data) do
    parsed = data |> put_context(existing) |> Message.new()

    existing
    |> Map.from_struct()
    |> Map.keys()
    |> Enum.reduce(existing, fn field, acc ->
      if present?(data, field), do: Map.put(acc, field, Map.get(parsed, field)), else: acc
    end)
  end

  # presences carry partial users: keep what we know, and never let a
  # missing flag clear a set one
  @spec user(struct(), struct()) :: struct()
  def user(existing, update) do
    update
    |> Map.from_struct()
    |> Enum.reduce(existing, fn
      {_field, nil}, acc ->
        acc

      {field, false}, acc when field in [:bot, :system] ->
        Map.put(acc, field, Map.get(acc, field) || false)

      {field, value}, acc ->
        Map.put(acc, field, value)
    end)
  end

  defp present?(data, :mention_members),
    do: Map.has_key?(data, "mention_members") or Map.has_key?(data, "mentions")

  defp present?(data, field), do: Map.has_key?(data, Atom.to_string(field))

  # the guild and author an update leaves out still shape how it parses
  defp put_context(data, existing) do
    data
    |> put_missing("guild_id", existing.guild_id)
    |> put_missing("author", existing.author)
  end

  defp put_missing(data, _key, nil), do: data
  defp put_missing(data, key, value), do: Map.put_new(data, key, to_raw(value))

  defp to_raw(%_{} = struct),
    do:
      struct |> Map.from_struct() |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)

  defp to_raw(value), do: value
end
